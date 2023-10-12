#!/bin/bash

DESCRIPTION="Check for possible Weka bucket count disparity"
# script type is single, parallel, sequential, or parallel-compare-backends
SCRIPT_TYPE="single"
JIRA_REFERENCE="WEKAPP-323045"
WTA_REFERENCE=""

RETURN_CODE=0

WEKA_VERSION=$(weka version current)
WEKA_VERSION_ARRAY=( ${WEKA_VERSION//./ } )   

if [[ ( ${WEKA_VERSION_ARRAY[0]} -eq 4 ) && \
      ( ${WEKA_VERSION_ARRAY[1]} -eq 2 ) && \
      ( ${WEKA_VERSION_ARRAY[2]} -eq 0 ) ]] ; then
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
