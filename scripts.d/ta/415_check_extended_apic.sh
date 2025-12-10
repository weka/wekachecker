#!/bin/bash

#set -ue # Fail with an error code if there's any sub-command/variable error

DESCRIPTION="Check that extended APIC is available for assigning IRQs"
# script type is single, parallel, sequential, or parallel-compare-backends
SCRIPT_TYPE="parallel"
JIRA_REFERENCE=""
WTA_REFERENCE=""
KB_REFERENCE=""

RETURN_CODE="0"

#check that extended APIC (or x2apic) is available, because it's required for more
# space for IRQs

grep -m1 -q -E '^flags.*(\<extapic|\<x2apic)' /proc/cpuinfo 2>/dev/null
EXT_APIC_STATUS=$?
if [[ ${EXT_APIC_STATUS} -eq 0 ]] ; then
    RETURN_CODE="0"
else
    RETURN_CODE="254"
    echo "There is no extended APIC available. This can prevent the assignment"
    echo "of enough IRQs to support all hardware, resulting in the kernel"
    echo "error message: vector space exhaustion"
    echo "A frequent cause of no extended APIC is the disabling of IOMMUs"
fi

if [[ ${RETURN_CODE} -eq "0" ]]; then
    echo "Extended APIC reports available"
else
    echo "No extended APIC available"
fi
exit ${RETURN_CODE}
