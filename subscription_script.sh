#! /bin/bash

## Script to attach Epsagon Role to kubernetes

ROLE_URL=https://raw.githubusercontent.com/epsagon/epsagon-k8s-role/master/epsagon-role.yaml

if [ `which wget` ] ; then
    wget $ROLE_URL
else
    if [ `which curl` ] ; then
        curl $ROLE_URL -o epsagon-role.yaml
    else
        if [ -z epsagon-role.yaml ] ; then
            echo "Could not get epsagon-role.yaml"
            echo "Please download the role from:"
            echo $ROLE_URL
            exit 1
        fi
    fi
fi
kubectl apply -f epsagon-role.yaml

if [ `which python` ] ; then
    kubectl -n epsagon-monitoring get secrets `kubectl -n epsagon-monitoring get secrets | grep 'epsagon-monitoring-token' | awk '{print $1}'` -o json | python -c 'import sys, json; print(json.load(sys.stdin)["data"]["token"])' > epsagon_role_token
else
    kubectl -n epsagon-monitoring get secrets `kubectl -n epsagon-monitoring get secrets | grep 'epsagon-monitoring-token' | awk '{print $1}'` -o json | grep '\"token\"' | cut -d: -f2 | cut -d'"' -f2 > epsagon_role_token
fi

echo ""
echo " --------"
echo ""
echo "The token for the epsagon role is: "
echo ""
cat epsagon_role_token
echo ""

rm -f epsagon_role_token
