#! /bin/bash

## Script to attach Epsagon Role to kubernetes

function usage {
    echo "Usage: epsagon_kubernetes_subscription.sh EPSAGON_TOKEN"
}

ROLE_FILE=epsagon-role.yaml
ROLE_URL=https://raw.githubusercontent.com/epsagon/epsagon-k8s-role/master/epsagon-role.yaml

function fetch_epsagon_role {
    echo "Fetching ${ROLE_FILE}"
    if [ -f $ROLE_FILE ] ; then
        echo "${ROLE_FILE} already exists - using that file"
        return 0
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

function send_to_epsagon {
    EPSAGON_TOKEN=$1
    ROLE_TOKEN=$2
    if [ $# == 3 ]; then
        CONTEXT=$3
        SERVER=`kubectl config view | grep -B 3 -E "[[:space:]]$CONTEXT\>" | grep -E "\<server: " | awk '{print $2}'`
        if [ -z $SERVER ] ; then
            echo "Could not find the server endpoint for context: ${CONTEXT}."
            echo " Please type the server endpoint:"
            read SERVER
        fi
    else
        # no context
        echo "Can't add a cluster without context"
    fi
    if [ `which curl` ] ; then
        curl -X POST https://api.epsagon.com/containers/k8s/add_cluster_by_token -d "{\"k8s_cluster_url\": \"$SERVER\", \"epsagon_token\": \"$EPSAGON_TOKEN\", \"cluster_token\": \"$ROLE_TOKEN\"}" -H 'Content-Type: application/json'
        echo ""
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

function apply_role {
    EPSAGON_TOKEN=$1
    KUBECTL="kubectl"
    if [ ! -z $2 ] ; then
        CONTEXT=$2
        KUBECTL="kubectl --context ${CONTEXT}"
        echo "Applying ${ROLE_FILE} to ${CONTEXT}"
    else
        echo "Applying ${ROLE_FILE}"
    fi
    echo ""
    ${KUBECTL} apply -f ${ROLE_FILE}

    SA_SECRET_NAME=`${KUBECTL} -n epsagon-monitoring get secrets | grep 'epsagon-monitoring-token' | awk '{print $1}'`
    if [ `which python` ] ; then
        ROLE_TOKEN=`${KUBECTL} -n epsagon-monitoring get secrets $SA_SECRET_NAME -o json | python -c 'import sys, json; print(json.load(sys.stdin)["data"]["token"])' | base64 --decode`
    else
        ROLE_TOKEN=`${KUBECTL} -n epsagon-monitoring get secrets $SA_SECRET_NAME -o json | grep '\"token\"' | cut -d: -f2 | cut -d'"' -f2 | base64 --decode`
    fi

    send_to_epsagon $EPSAGON_TOKEN $ROLE_TOKEN $CONTEXT

}

function apply_epsagon_on_all_contexts {
    echo "Welcome to Epsagon!"
    NUMBER_OF_CONTEXTS=$((`kubectl config get-contexts | wc -l` - 1 ))
    for context in `kubectl config get-contexts | tail -${NUMBER_OF_CONTEXTS} | sed s/^*//  | awk {'print $1'}`; do
        echo ""
        echo "Now installing Epsagon to: $context"
        echo -n "Would you like to proceed? [Y/N] "
        read answer
        if [ "$answer" == "Y" ]; then
            apply_role $1 $context
        else
            continue
        fi
    done
}

if [ $# -ne 1 ] ; then
    usage
else
    fetch_epsagon_role
    apply_epsagon_on_all_contexts $1
fi
