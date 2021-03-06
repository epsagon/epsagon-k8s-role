#! /bin/bash

## Script to attach Epsagon Role to kubernetes

function usage {
    echo "Usage: epsagon_kubernetes_subscription.sh EPSAGON_TOKEN"
}

ROLE_FILE=epsagon-role.yaml
ROLE_URL=https://raw.githubusercontent.com/epsagon/epsagon-k8s-role/master/epsagon-role.yaml
RANCHER_TOKEN=""

function track {
    EPSAGON_TOKEN=$1
    EVENT_NAME=$2
    EVENT_DATA=$3
    curl -s -X POST https://track.epsagon.com/production/record -d "{\"event_name\": \"$EVENT_NAME\", \"token\": \"$EPSAGON_TOKEN\", \"event_data\": $EVENT_DATA}" -H 'Content-Type: application/json' > /dev/null
}

function fetch_epsagon_role {
    echo "Fetching ${ROLE_FILE}"
    if [ -f $ROLE_FILE ] ; then
        echo "${ROLE_FILE} already exists - replacing it"
        rm -f $ROLE_FILE
    fi
    if [ `which wget` ] ; then
        wget $ROLE_URL
    else
        if [ `which curl` ] ; then
            curl $ROLE_URL -o ${ROLE_FILE}
        else
            if [ -s ${ROLE_FILE} ] ; then
                echo "Could not get ${ROLE_FILE}"
                echo "Please download the role from:"
                echo $ROLE_URL
                exit 1
            fi
        fi
    fi
}

function test_connection {
    SERVER=$1
    EPSAGON_TOKEN=$2
    ROLE_TOKEN=$3
    echo "Testing Epsagon connection to server ${SERVER}..."
    RESULT=`curl -X POST https://api.epsagon.com/containers/k8s/check_cluster_connection -d "{\"k8s_cluster_url\": \"$SERVER\", \"epsagon_token\": \"$EPSAGON_TOKEN\", \"cluster_token\": \"$ROLE_TOKEN\"}" -H 'Content-Type: application/json'`
    #Expected Response format:
    # {
    #   "connection_status": "successful" / "failed",
    #   "connection_failure_reason": "" # Optional, failure reason string, only relevant if "status"=="failed"
    # }
    CONNECTION_STATUS=`echo $RESULT | grep -o -E "\"connection_status\": \"[^\"]+\"" | awk -F\: '{print $2}'`
    CONNECTION_STATUS=`echo $CONNECTION_STATUS | xargs`
    if [ ! -z $CONNECTION_STATUS ]; then
        if [ "$CONNECTION_STATUS" == "successful" ]; then
            echo "Succesfully connected to server ${SERVER}"
            return 0
        else
            ERROR=`echo $RESULT | grep -o -E "\"connection_failure_reason\": \".+\"" | awk '{print $2}'`
            echo "Integration failed, see https://docs.epsagon.com/docs/environments-kubernetes. Error message: ${ERROR}"
            return 1
        fi
    else
        echo "Connection to Epsagon failed, please see: https://docs.epsagon.com/docs/environments-kubernetes"
        track $EPSAGON_TOKEN "K8s Integration Failed" "{\"K8s Cluster URL\": \"$SERVER\", \"Failure Reason\": \"Connection to Epsagon for connection check failed\"}"
        return 1
    fi
}

function send_to_epsagon {
    EPSAGON_TOKEN=$1
    ROLE_TOKEN=$2
    CONTEXT=$3
    if [ $# == 4 ]; then
        CONFIG=$4
        KUBECTL="kubectl config view --kubeconfig ${CONFIG}"
    else
        KUBECTL="kubectl config view"
    fi
    SERVER=`${KUBECTL} --context ${CONTEXT} | grep -B 3 -E "[[:space:]]$CONTEXT\>" | grep -E "\<server: " | awk '{print $2}' | head -1`
    if [ -z $SERVER ] ; then
        echo "Could not find the server endpoint for context: ${CONTEXT}."
        echo " Please type the server endpoint:"
        read SERVER
        track $EPSAGON_TOKEN "K8s Integration Server Auto Detect Failed" "{\"Context\": \"$CONTEXT\", \"Manually Entered Server URL\": \"$SERVER\"}"
    fi
    if [ `which curl` ] ; then
        if test_connection $SERVER $EPSAGON_TOKEN $ROLE_TOKEN; then
            echo "Integrating cluster into epsagon..."
            curl -X POST https://api.epsagon.com/containers/k8s/add_cluster_by_token -d "{\"k8s_cluster_url\": \"$SERVER\", \"epsagon_token\": \"$EPSAGON_TOKEN\", \"cluster_token\": \"$ROLE_TOKEN\"}" -H 'Content-Type: application/json'
            echo ""
        fi
    else
        echo "Could not find 'curl' command to send data to epsagon, please enter manually"
        echo "server=${SERVER}"

        echo ""
        echo "--------"
        echo ""
        echo "The token for the epsagon role is: "
        echo ""
        echo $ROLE_TOKEN
        echo ""
    fi
}

function remove_mutation_controller {
    if [ -d epsagon-mutation-controller ] ; then
        rm -rf epsagon-mutation-controller
    fi
}

function clone_mutation_controller {
    remove_mutation_controller
    if [ `which git` ] ; then
        git clone https://github.com/epsagon/epsagon-mutation-controller.git
    fi
}


function apply_mutation_controller {
    EPSAGON_TOKEN=$1
    CONTEXT=$2
    if [ -d epsagon-mutation-controller ] ; then
        ORIGINAL_DIR=`pwd`
        cd epsagon-mutation-controller/kubernetes
        if [ $# == 3 ] ; then
            CONFIG=$3
            source ./deploy.sh --context $CONTEXT --kubeconfig $CONFIG --token $EPSAGON_TOKEN
        else
            source ./deploy.sh --context $CONTEXT --token $EPSAGON_TOKEN
        fi
        cd $ORIGINAL_DIR
    fi
}

function apply_role {
    EPSAGON_TOKEN=$1
    CONTEXT=$2
    KUBECTL="kubectl --context ${CONTEXT}"
    if [ ! -z $3 ] ; then
        CONFIG=$3
        KUBECTL="kubectl --context ${CONTEXT} --kubeconfig=${CONFIG}"
    fi
    echo "Applying ${ROLE_FILE} to ${CONTEXT}"
    echo ""
    ${KUBECTL} apply -f ${ROLE_FILE}
    if [ ! -z $RANCHER_TOKEN ] ; then
        send_to_epsagon $EPSAGON_TOKEN $RANCHER_TOKEN $CONTEXT $CONFIG
    else
        SA_SECRET_NAME=`${KUBECTL} -n epsagon-monitoring get secrets | grep 'epsagon-monitoring-token' | awk '{print $1}'`
        if [ `which python` ] ; then
            ROLE_TOKEN=`${KUBECTL} -n epsagon-monitoring get secrets $SA_SECRET_NAME -o json | python -c 'import sys, json; print(json.load(sys.stdin)["data"]["token"])' | base64 --decode`
        else
            ROLE_TOKEN=`${KUBECTL} -n epsagon-monitoring get secrets $SA_SECRET_NAME -o json | grep '\"token\"' | cut -d: -f2 | cut -d'"' -f2 | base64 --decode`
        fi

        if [ -z $ROLE_TOKEN ]; then
            echo "Deploying epsagon role to the cluster failed - could not extract role token"
            track $EPSAGON_TOKEN "K8s Integration Failed" "{\"Context\": \"$CONTEXT\", \"Failure Reason\": \"could not extract role token\"}"
        else
            send_to_epsagon $EPSAGON_TOKEN $ROLE_TOKEN $CONTEXT $CONFIG
        fi
    fi

}

function does_config_file_exist {
    if [ -f ~/.kube/config ]; then
        return 0
    fi
    for i in `echo $KUBECONFIG | tr ':' '\n'`; do
        if [ -f "$i" ]; then
            return 0
        fi
    done
    return 1
}

function is_positive_answer {
    answer=$1
    if [ ${answer} == 'y' ] ; then
        answer='Y'
    fi
    if [ ${answer} == 'Y' ] ; then
        return 0;
    fi
    return 1;
}

function apply_epsagon_on_all_contexts {
    echo "          Welcome to Epsagon!"
    echo "
             ######               # ##  
             ######              #####  
           ############## #     ######  
           ###################  ######  
      #### ###########################  
     ##### ###########################  
 ### ################################## 
 ####  ###     ##   ###################  
 ###                 #################   
                          ##########    
                          ############  
                             ###    ###"

    config_file_path=""
    KUBECTL="kubectl"
    if [ ! does_config_file_exist ] ; then
        echo "Could not find any config file for kubectl"
        echo "Please insert your kubectl config file path:"
        read config_file_path
        KUBECTL="${KUBECTL} --kubeconfig ${config_file_path}"
    fi
    
    echo -n "Are you using Rancher Management System? [Y/N] "
    read answer
    is_positive_answer $answer
    if [ $? -eq 0 ] ; then
        echo "Please insert your Rancher API Key:"
        read RANCHER_TOKEN
        track $1 "K8s Integration With Rancher" "{\"Started\": \"True\"}"
    fi

    echo "Available clusters:"
    index=1
    for context in `${KUBECTL} config get-contexts --no-headers | awk {'gsub(/^\*/, ""); print $1'}`; do
        echo "${index}. $context"
        ((index = index + 1))
    done

    echo ""
    echo "Choose clusters to integrate. Use spaces for multiple clusters, e.g: 1 2 3..."
    read -a choices

    index=1
    for context in `${KUBECTL} config get-contexts --no-headers | awk {'gsub(/^\*/, ""); print $1'}`; do
        if [[ " ${choices[@]} " =~ " ${index} " ]]; then
            echo ""
            echo "Now installing Epsagon to: $context"
            apply_role $1 $context $config_file_path
        fi
        ((index = index + 1))
    done
}


track $1 "K8s Integration Started" "{\"Started\": \"True\"}"
if [ $# -ne 1 ] ; then
    usage
else
    fetch_epsagon_role
    apply_epsagon_on_all_contexts $1
fi
