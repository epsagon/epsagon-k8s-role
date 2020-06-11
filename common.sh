#! /bin/bash
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
