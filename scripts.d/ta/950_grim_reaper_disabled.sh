#!/bin/bash

#set -ueo pipefail # Fail with an error code if there's any sub-command/variable error

DESCRIPTION="Check if WEKA's Grim Reaper is (expected to be) disabled"
# script type is single, parallel, sequential, or parallel-compare-backends
SCRIPT_TYPE="single"
JIRA_REFERENCE=""
WTA_REFERENCE="WTA20261116"
KB_REFERENCE=""

RETURN_CODE=0

# Check if we can run weka commands
weka status &> /dev/null
RC=$?

case ${RC} in
    0)
        ;;
    127)
        echo "WEKA not found."
        exit 254
        ;;
    41)
        echo "Unable to login to Weka cluster."
        exit 254
        ;;
    *)
        echo "ERROR: Not able to run weka commands (weka status returned ${RC})."
        exit 254
        ;;
esac

RETURN_CODE=254

##############################################################
# Check that a cluster installed on or after the arbitrary
# cut-off 2026-11-01 has grim reaper disabled (it should)

CUTOFF_USECS=1793491200000000   # 2026-11-01 00:00:00 UTC

# installTime doesn't exist on older clusters, in which case this command
# exits non-zero. That is not an error: it just means the cluster is old.
CLUSTER_BORN_ON=$(weka debug config show clusterInfo.installTime.usecs 2>/dev/null)

if [[ ! "${CLUSTER_BORN_ON}" =~ ^[0-9]+$ ]] || (( CLUSTER_BORN_ON < CUTOFF_USECS )); then
    # No (readable) installTime means the cluster is old
    echo "This cluster was installed before the cut-off; no check required"
    exit 0
fi

if ! GR_ENABLED=$(weka debug config show runtimeInfo.grimReaperEnabled); then
    echo "Could not read grim reaper state"
    exit 1
fi

if [[ "${GR_ENABLED}" == "false" ]]; then
    echo "This cluster was installed after the cut-off and grim reaper has been disabled"
    exit 0
fi

echo "This cluster was installed after the cut-off; grim reaper should be disabled"
echo "Please contact WEKA Customer Success for advice."
exit 1
