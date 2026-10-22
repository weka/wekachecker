#!/bin/bash

# No -e: this script inspects the exit codes of the commands it runs.
set -uo pipefail

DESCRIPTION="Examine the number of Raft agents used vs maximum"
SCRIPT_TYPE="single"
JIRA_REFERENCE=""
WTA_REFERENCE=""
RETURN_CODE=0

RAFT_AGENTS_PER_BUCKET=5
MAX_RAFT_AGENTS_PER_COMPUTE=180

if ! command -v weka &> /dev/null; then
    echo "WEKA not found"
    exit 254
fi

weka status &> /dev/null
RC=$?
case ${RC} in
    0)  ;;
    41) echo "Unable to login into Weka cluster."
        exit 254
        ;;
    *)  echo "ERROR: Not able to run weka commands (weka status returned ${RC})"
        exit 254
        ;;
esac

# The "buckets" object has the same shape on 4.4 and 6.x, so take the count from
# there rather than from the human-readable status line.
WEKA_BUCKET_COUNT=""
BUCKETS_ACTIVE=""
BUCKETS_INDENT=""

while IFS= read -r LINE; do
    if [[ -z ${BUCKETS_INDENT} && ${LINE} =~ ^([[:space:]]*)\"buckets\":[[:space:]]*\{ ]]; then
        BUCKETS_INDENT=${BASH_REMATCH[1]}
        continue
    fi
    if [[ -n ${BUCKETS_INDENT} ]]; then
        if [[ ${LINE} =~ ^${BUCKETS_INDENT}\},?$ ]]; then
            break
        fi
        [[ ${LINE} =~ \"total\":[[:space:]]*([0-9]+) ]] && WEKA_BUCKET_COUNT=${BASH_REMATCH[1]}
        [[ ${LINE} =~ \"active\":[[:space:]]*([0-9]+) ]] && BUCKETS_ACTIVE=${BASH_REMATCH[1]}
    fi
done < <(weka status -J 2> /dev/null)

[[ -z ${WEKA_BUCKET_COUNT} ]] && WEKA_BUCKET_COUNT=${BUCKETS_ACTIVE}

if [[ -z ${WEKA_BUCKET_COUNT} ]]; then
    # Last resort: "... (18 io-nodes UP, 24 Buckets UP)" on the io status line.
    WEKA_BUCKET_COUNT=$(weka status 2> /dev/null \
        | sed -n 's/.*[^0-9]\([0-9][0-9]*\) Buckets.*/\1/p' | head -n1)
fi

# 'uid' is a valid column on both 4.4 and 6.x; 4.4 calls the identifier 'id' and 6.x
# renamed it to 'process', so either of those fails outright on the other version.
WEKA_COMPUTE_PROCESS_COUNT=$(weka cluster process -b -F role=COMPUTE --no-header -o uid 2> /dev/null \
    | grep -c .)

if [[ -z ${WEKA_BUCKET_COUNT} ]] || (( WEKA_BUCKET_COUNT == 0 )); then
    echo "Unable to determine the number of buckets from 'weka status'."
    echo "Recommended Resolution: check 'weka status' is healthy on this cluster."
    exit 254
fi

if (( WEKA_COMPUTE_PROCESS_COUNT == 0 )); then
    echo "Unable to determine the number of backend COMPUTE processes."
    echo "Recommended Resolution: check 'weka cluster process -b -F role=COMPUTE' returns rows."
    exit 254
fi

WEKA_RAFT_AGENTS=$(( WEKA_BUCKET_COUNT * RAFT_AGENTS_PER_BUCKET ))
WEKA_MAX_RAFT_AGENTS=$(( WEKA_COMPUTE_PROCESS_COUNT * MAX_RAFT_AGENTS_PER_COMPUTE ))

if (( WEKA_RAFT_AGENTS > WEKA_MAX_RAFT_AGENTS )); then
    echo "The maximum number of raft agents recommended per compute node is ${MAX_RAFT_AGENTS_PER_COMPUTE}. This cluster requires ${WEKA_RAFT_AGENTS} in total"
    echo " (${WEKA_BUCKET_COUNT} buckets x ${RAFT_AGENTS_PER_BUCKET}), against a recommended ceiling of ${WEKA_MAX_RAFT_AGENTS} for ${WEKA_COMPUTE_PROCESS_COUNT} compute processes."
    echo "Recommended resolution: scale out your cluster by adding more compute processes or perhaps backend WEKA servers"
    RETURN_CODE=254
fi

if [[ ${RETURN_CODE} -eq 0 ]]; then
    echo "Fewer than the recommended maximum number of raft agents per compute node in use"
    echo " (${WEKA_RAFT_AGENTS} raft agents for ${WEKA_BUCKET_COUNT} buckets, ceiling ${WEKA_MAX_RAFT_AGENTS} for ${WEKA_COMPUTE_PROCESS_COUNT} compute processes)"
fi

exit ${RETURN_CODE}
