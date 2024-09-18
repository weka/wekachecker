#!/bin/bash

set -ue # Fail with an error code if there's any sub-command/variable error

DESCRIPTION="Check Weka DPDK network devices have IP gateways"
# script type is single, parallel, sequential, or parallel-compare-backends
SCRIPT_TYPE="parallel"

RETURN_CODE=0

for WEKA_CONTAINER in $(sudo weka local ps --output name --no-header | grep -vw -e envoy -e ganesha -e samba -e smbw -e s3); do
    DEVICES_WITH_NO_GATEWAY=""
    # skip network devices beginning with ib, as a weak attempt at identifying infiniband interfaces
    for NET_DEVICE in $(weka local resources net -C ${WEKA_CONTAINER} --stable | awk 'NR>1{print $1}' | grep -v -e ^ib); do
        if [[ -n ${NET_DEVICE} ]]; then
            if weka local resources net -C drives0 -J --stable | grep -A 1 -w ${NET_DEVICE} | grep gateway | grep -q \"\"; then
                DEVICES_WITH_NO_GATEWAY="${DEVICES_WITH_NO_GATEWAY} ${NET_DEVICE} "
            fi
        fi
    done
    if [[ -n ${DEVICES_WITH_NO_GATEWAY} ]]; then
        echo "The container ${WEKA_CONTAINER} has the network devices ${DEVICES_WITH_NO_GATEWAY}"
        echo "defined without an IP gateway - this might not be a mistake but means Weka"
        echo "POSIX traffic will not leave this subnet."
        echo "The likely fix for this is to do weka local resources net remove for each device,"
        echo "then add back in with weka local resource net add <DEVNAME> --gateway ... --netmask .."
        echo
        RETURN_CODE=254
    fi
done

if [[ ${RETURN_CODE} -eq 0 ]]; then
    echo "All Weka containers have network devices with gateways"
fi

exit ${RETURN_CODE}
