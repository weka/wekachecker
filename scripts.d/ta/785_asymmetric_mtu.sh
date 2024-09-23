#!/bin/bash

#set -ue # Fail with an error code if there's any sub-command/variable error

DESCRIPTION="Check for clients that are reporting differences in IN_MTU vs OUT_MTU"
SCRIPT_TYPE="single"
JIRA_REFERENCE="WEKAPP-438140"
WTA_REFERENCE=""
KB_REFERENCE=""
RETURN_CODE=0

# Last modified: 2024-09-23

for CLIENT_PROCESS in $(weka cluster process --no-header --output id); do 
    if [[ $(weka debug net peers --no-header ${CLIENT_PROCESS} --output inMTU,outMTU  | awk '{if($1 != $2) {print "yes"}}') == "yes" ]]; then
        host=$(weka cluster process ${CLIENT_PROCESS} --no-header -o hostname)
        echo "WARN: Asymmetric MTU detected for ${host}, process id ${CLIENT_PROCESS}"
        RETURN_CODE=254
    fi
done

if [[ ${RETURN_CODE} -eq 0 ]]; then
    echo "No asymmetric MTUs detected."
fi

exit ${RETURN_CODE}