#!/bin/bash

#set -ue # Fail with an error code if there's any sub-command/variable error

DESCRIPTION="Check for network mode consistency"
SCRIPT_TYPE="single"
JIRA_REFERENCE=""
WTA_REFERENCE=""
KB_REFERENCE=""
RETURN_CODE=0

declare -A NETWORK_MODES

# Check if we can run weka commands
weka status &> /dev/null
if [[ $? -ne 0 ]]; then
    echo "ERROR: Not able to run weka commands"
    exit 254
elif [[ $? -eq 127 ]]; then
    echo "WEKA not found"
    exit 254
elif [[ $? -eq 41 ]]; then
    echo "Unable to login into Weka cluster."
    exit 254
fi


# Iterate over backend weka containers
for ROLE in COMPUTE DRIVES; do
    while read NETMODE; do
        for MODE in $NETMODE; do
            if [[ $MODE != "/" ]]; then
                NETWORK_MODES[$MODE]=$((${NETWORK_MODES[$MODE]:-0}+1))
            fi
        done
    done < <(weka cluster process -b -F role=$ROLE -o netmode --no-header)
done

for MODE in "${!NETWORK_MODES[@]}"; do
    num_occurrences=$((${num_occurrences:-0}+${NETWORK_MODES[$MODE]}))
    mode_status+="$MODE(${NETWORK_MODES[$MODE]}) "
done

if [ $((num_occurrences % ${#NETWORK_MODES[@]})) -ne 0 ]; then
    RETURN_CODE=254
    echo "WARNING: Backend process network modes are inconsistent - $mode_status"
fi

if [[ $RETURN_CODE -eq 0 ]]; then
    echo "Backend process network modes are consistent."
fi

exit $RETURN_CODE