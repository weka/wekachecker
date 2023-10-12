#!/bin/bash

DESCRIPTION="Check for batch client upgrade issues"
# script type is single, parallel, sequential, or parallel-compare-backends
SCRIPT_TYPE="single"
JIRA_REFERENCE="WEKAPP-318113"
WTA_REFERENCE=""

RETURN_CODE=0

# Use core-util's sort -V to dermine if version $1 is <= version $2
verlte() {
    [  "$1" = "$(echo -e "$1\n$2" | sort -V | head -n1)" ]
}
verlt() {
    [ "$1" = "$2" ] && return 1 || verlte $1 $2
}

WEKA_VERSION=$(weka version current)

# compare between 4.1.0 and 4.2.1
if ( verlt ${WEKA_VERSION} "4.2.1" ) && ( verlte "4.1.0" ${WEKA_VERSION} ) ; then
    RETURN_CODE=1
    echo "The current Weka version ${WEKA_VERSION} is potentially susceptible"
    if [[ ! -z "${WTA_REFERENCE}" ]]; then
        echo "to ${JIRA_REFERENCE}, discussed in ${WTA_REFERENCE}"
    else
        echo "to ${JIRA_REFERENCE}"
    fi
    echo "This does not necessarily prove a problem, and should be investigated"
fi

exit ${RETURN_CODE}
