#!/bin/bash

# No -e: this script inspects the exit codes of the commands it runs.
set -uo pipefail

DESCRIPTION="Check tcp connectivity to management ports of backends."
SCRIPT_TYPE="single"
JIRA_REFERENCE=""
WTA_REFERENCE=""
KB_REFERENCE=""
RETURN_CODE=0

# Assumption / limitations
#  Must permit ICMP (ping)
#  Only performs TCP pings against the management ports (base_port + 0)
#  IPv4 only

# ping -W is in SECONDS, not milliseconds.
PING_TIMEOUT=1
CONNECT_TIMEOUT=2

if ! command -v weka &> /dev/null; then
    echo "WEKA not found"
    exit 254
fi

if (( BASH_VERSINFO[0] < 4 )); then
    echo "ERROR: bash 4 or newer is required to run this check."
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

# A filtered port never refuses the connection, it simply never answers, so the
# attempt has to be bounded or the check hangs for the kernel's full SYN timeout.
if command -v timeout &> /dev/null; then
    TCP_PROBE=(timeout "${CONNECT_TIMEOUT}" bash -c 'exec 3<>/dev/tcp/"$0"/"$1"')
else
    TCP_PROBE=(bash -c 'exec 3<>/dev/tcp/"$0"/"$1"')
fi

# One pass over every backend container instead of two 'weka cluster container'
# calls each. 4.4 calls the management port "mgmt_port"; 6.x renamed it to "port".
# The rest of the shape is identical, and neither version has any other *port* key
# at this level to be confused with.
PORT=""
IPS=""
IN_IPS=""
CONTAINERS_WITHOUT_PORT=0

parse_containers() {
    while IFS= read -r LINE; do
        if [[ ${LINE} == "    {" ]]; then
            PORT=""
            IPS=""
            IN_IPS=""
            continue
        fi

        if [[ ${LINE} =~ ^\ {4}\},?$ ]]; then
            # This runs in a subshell, so a container with no port is reported as a
            # marker line rather than by a counter the caller would never see.
            if [[ -z ${PORT} && -n ${IPS} ]]; then
                printf "NOPORT\n"
            elif [[ -n ${PORT} && -n ${IPS} ]]; then
                printf '%s%s\n' "${PORT}" "${IPS}"
            fi
            continue
        fi

        if [[ -n ${IN_IPS} ]]; then
            if [[ ${LINE} =~ ^\ {8}\],?$ ]]; then
                IN_IPS=""
            elif [[ ${LINE} =~ \"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\" ]]; then
                IPS="${IPS} ${BASH_REMATCH[1]}"
            fi
            continue
        fi

        if [[ ${LINE} =~ ^\ {8}\"ips\":[[:space:]]*\[[[:space:]]*\],?$ ]]; then
            continue
        elif [[ ${LINE} =~ ^\ {8}\"ips\":[[:space:]]*\[ ]]; then
            IN_IPS=1
            continue
        fi

        [[ ${LINE} =~ ^\ {8}\"(mgmt_port|port)\":[[:space:]]*([0-9]+) ]] && PORT=${BASH_REMATCH[2]}
    done < <(weka cluster container -b -J 2> /dev/null)
}

declare -A CHECKED=()
TARGETS=0

# Perform the port checks
while read -r PORT_FIELD IP_LIST; do
    if [[ ${PORT_FIELD} == "NOPORT" ]]; then
        CONTAINERS_WITHOUT_PORT=$(( CONTAINERS_WITHOUT_PORT + 1 ))
        continue
    fi

    for IP in ${IP_LIST}; do
        # The same address can be listed by more than one container; probe it once.
        KEY="${IP}|${PORT_FIELD}"
        [[ -n ${CHECKED[${KEY}]:-} ]] && continue
        CHECKED[${KEY}]=1
        TARGETS=$(( TARGETS + 1 ))

        # If it does not respond to a ping assume the IP is not valid / reachable.
        if ping -c 1 -q -W "${PING_TIMEOUT}" "${IP}" &> /dev/null; then
            if ! "${TCP_PROBE[@]}" "${IP}" "${PORT_FIELD}" &> /dev/null; then
                echo "WARN: Unable to connect to ${IP} tcp/${PORT_FIELD}"
                echo "Recommended Resolution: There is likely something blocking network communication between"
                echo "this host and ${IP} tcp/${PORT_FIELD}. Please review network connectivity and/or firewalls"
                echo "In particular DDOS-style protection on switches may prevent communication"
                RETURN_CODE=254
            fi
        else
            echo "WARN: Unable to ping ${IP}"
            RETURN_CODE=254
        fi
    done
done < <(parse_containers)

if (( CONTAINERS_WITHOUT_PORT > 0 )); then
    echo "WARN: ${CONTAINERS_WITHOUT_PORT} backend container(s) reported no management port, and were not checked."
    echo "Recommended Resolution: check 'weka cluster container -b -J' returns a port for every container."
    RETURN_CODE=254
fi

if (( TARGETS == 0 )); then
    echo "No backend management addresses were found to check."
    echo "Recommended Resolution: check 'weka cluster container -b' lists the backends."
    exit 254
fi

if [[ ${RETURN_CODE} -eq 0 ]]; then
    echo "No backend management ports blocked (${TARGETS} address/port pairs checked)."
fi

exit ${RETURN_CODE}
