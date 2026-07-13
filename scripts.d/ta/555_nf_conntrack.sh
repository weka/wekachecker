#!/bin/bash

DESCRIPTION="Check whether connection tracking (nf_conntrack) is active"
SCRIPT_TYPE="parallel"
JIRA_REFERENCE="WEKAPP-639825"
WTA_REFERENCE=""
KB_REFERENCE=""
RETURN_CODE=0

# Connection tracking adds overhead to every packet handled by the kernel
# network stack, and if the tracking table fills up, new connections are
# dropped. See WEKAPP-639825.

CONNTRACK_COUNT_FILE="/proc/sys/net/netfilter/nf_conntrack_count"
CONNTRACK_MAX_FILE="/proc/sys/net/netfilter/nf_conntrack_max"

# Table fill percentage at which we escalate from WARN to FAIL
FILL_LIMIT_PERCENT=80

if [[ ! -d /sys/module/nf_conntrack || ! -r ${CONNTRACK_COUNT_FILE} || ! -r ${CONNTRACK_MAX_FILE} ]]; then
    echo "nf_conntrack is not active on this host."
    exit 0
fi

COUNT=$(cat ${CONNTRACK_COUNT_FILE})
MAX=$(cat ${CONNTRACK_MAX_FILE})

RETURN_CODE=254
echo "nf_conntrack (connection tracking) is active on this host."
echo "This can affect WEKA traffic. See ${JIRA_REFERENCE}."
echo "Currently tracking ${COUNT} connections, of a maximum ${MAX}."

if [[ ${MAX} -gt 0 ]]; then
    FILL_PERCENT=$(( COUNT * 100 / MAX ))
    echo "The connection tracking table is ${FILL_PERCENT}% full."
    if [[ ${FILL_PERCENT} -ge ${FILL_LIMIT_PERCENT} ]]; then
        RETURN_CODE=1
        echo "The connection tracking table is close to its maximum size."
        echo "New connections risk being dropped when the table is full."
    fi
fi

exit ${RETURN_CODE}
