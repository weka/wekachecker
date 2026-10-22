#!/bin/bash

# No -e: this script inspects the exit codes of the commands it runs.
set -uo pipefail

DESCRIPTION="Check we have sufficient capacity in case of failure"
# script type is single, parallel, sequential, or parallel-compare-backends
SCRIPT_TYPE="single"
REFERENCE=""

RETURN_CODE=0

if ! command -v weka &> /dev/null; then
    echo "WEKA not found."
    exit 254
fi

weka status &> /dev/null
RC=$?
case ${RC} in
    0)  ;;
    41) echo "Unable to login to Weka cluster."
        exit 254
        ;;
    *)  echo "ERROR: Not able to run weka commands (weka status returned ${RC})."
        exit 254
        ;;
esac

# 4.4 reports these as top-level keys ("hot_spare", "stripe_data_drives"); 6.x moved
# them into a "stripe" object and dropped the underscore ("hotspare", "data"). Read
# both shapes in one pass, and never match "hot_spare_bytes", which is a capacity.
HOT_SPARE=""
NUM_DATA_DISKS=""
STRIPE_INDENT=""

while IFS= read -r LINE; do
    if [[ -z ${STRIPE_INDENT} && ${LINE} =~ ^([[:space:]]*)\"stripe\":[[:space:]]*\{ ]]; then
        STRIPE_INDENT=${BASH_REMATCH[1]}
        continue
    fi

    if [[ -n ${STRIPE_INDENT} ]]; then
        if [[ ${LINE} =~ ^${STRIPE_INDENT}\},?$ ]]; then
            STRIPE_INDENT=""
            continue
        fi
        [[ ${LINE} =~ \"hotspare\":[[:space:]]*([0-9]+) ]] && HOT_SPARE=${BASH_REMATCH[1]}
        [[ ${LINE} =~ \"data\":[[:space:]]*([0-9]+) ]] && NUM_DATA_DISKS=${BASH_REMATCH[1]}
        continue
    fi

    [[ ${LINE} =~ \"hot_spare\":[[:space:]]*([0-9]+) ]] && HOT_SPARE=${BASH_REMATCH[1]}
    [[ ${LINE} =~ \"stripe_data_drives\":[[:space:]]*([0-9]+) ]] && NUM_DATA_DISKS=${BASH_REMATCH[1]}
done < <(weka status -J 2> /dev/null)

if [[ -z ${HOT_SPARE} ]]; then
    echo "Unable to read the hot spare count from 'weka status -J'."
    echo "Recommended Resolution: check 'weka status' is healthy on this cluster."
    exit 254
fi

if (( HOT_SPARE >= 1 )); then
    echo "We have at least one hot spare configured, no further checking required"
    exit 0
fi

# We have 0 hot-spares, which is likely at least bad
echo "No hot spare capacity is configured on this cluster."
RETURN_CODE=254

if [[ -z ${NUM_DATA_DISKS} ]] || (( NUM_DATA_DISKS < 2 )); then
    echo "Unable to read a usable stripe width from 'weka status -J', so the per-filesystem"
    echo "fill level could not be checked."
    echo "Recommended Resolution: allocate hot-spare capacity."
    exit 254
fi

# What happens if we lose 1 FD?
THRESHOLD_FILL_LEVEL=$(( (NUM_DATA_DISKS - 1) * 100 / NUM_DATA_DISKS ))

FS_OVER_THRESHOLD=0
FS_NAME=""
USED_SSD=""
AVAILABLE_SSD=""

# One pass over every filesystem rather than two 'weka fs' calls per filesystem.
while IFS= read -r LINE; do
    if [[ ${LINE} == "    {" ]]; then
        FS_NAME=""
        USED_SSD=""
        AVAILABLE_SSD=""
        continue
    fi

    if [[ ${LINE} =~ ^\ {4}\},?$ ]]; then
        [[ -z ${FS_NAME} || -z ${USED_SSD} || -z ${AVAILABLE_SSD} ]] && continue
        # A filesystem with no SSD capacity has no fill level to compare.
        (( AVAILABLE_SSD == 0 )) && continue

        RATIO=$(( USED_SSD * 100 / AVAILABLE_SSD ))
        if (( RATIO >= THRESHOLD_FILL_LEVEL )); then
            echo "Filesystem ${FS_NAME} is ${RATIO}% full (threshold ${THRESHOLD_FILL_LEVEL}%), and may suffer write hanging in the loss of a failure domain"
            FS_OVER_THRESHOLD=$(( FS_OVER_THRESHOLD + 1 ))
        fi
        continue
    fi

    if [[ ${LINE} =~ ^\ {8}\"name\":[[:space:]]*\"(.*)\",?$ ]]; then
        FS_NAME=${BASH_REMATCH[1]}
    elif [[ ${LINE} =~ ^\ {8}\"used_ssd\":[[:space:]]*([0-9]+) ]]; then
        USED_SSD=${BASH_REMATCH[1]}
    elif [[ ${LINE} =~ ^\ {8}\"available_ssd\":[[:space:]]*([0-9]+) ]]; then
        AVAILABLE_SSD=${BASH_REMATCH[1]}
    fi
done < <(weka fs -J 2> /dev/null)

if (( FS_OVER_THRESHOLD > 0 )); then
    echo "${FS_OVER_THRESHOLD} filesystem(s) are filled beyond the capacity calculated to be"
    echo " available if a single failure domain were to be lost."
    echo "This might lead to write hangs in the case of hardware failure."
    echo "Recommended Resolution: Allocate hot-spare capacity or otherwise increase free space"
else
    echo "No filesystem is filled beyond the ${THRESHOLD_FILL_LEVEL}% that would remain available after"
    echo " the loss of a failure domain, but there is no hot spare to rebuild into."
    echo "Recommended Resolution: Allocate hot-spare capacity"
fi

exit ${RETURN_CODE}
