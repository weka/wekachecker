#!/bin/bash

# No -e: this script inspects the exit codes of the commands it runs.
set -uo pipefail

DESCRIPTION="NFSW FIPs validation"
# script type is single, parallel, sequential, or parallel-compare-backends
SCRIPT_TYPE="parallel"
JIRA_REFERENCE="WEKAPP-471021"
WTA_REFERENCE=""
KB_REFERENCE=""

RETURN_CODE=0

# WEKAPP-471021: a floating IP whose serial climbs past this stops converging.
MAX_FIP_VERSION=16384

if ! command -v weka &> /dev/null; then
    echo "WEKA not found."
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
    41) echo "Unable to login to Weka cluster."
        exit 254
        ;;
    *)  echo "ERROR: Not able to run weka commands (weka status returned ${RC})."
        exit 254
        ;;
esac

HOSTNAME_SHORT=$(hostname)

# These columns were renamed in 6.x: 'weka cluster process' lost "id" in favour of
# "process", and the interface-group assignment lists "container" where 4.4 listed
# "host". Probe instead of version-matching.
if weka cluster process --no-header -o process &> /dev/null; then
    PROCESS_COL="process"
else
    PROCESS_COL="id"
fi

if weka nfs interface-group assignment --no-header -o ip,container,port &> /dev/null; then
    ASSIGN_COL="container"
else
    ASSIGN_COL="host"
fi

# Container ids belonging to this host, used to pick our rows out of the
# cluster-wide assignment table.
declare -A LOCAL_CONTAINERS=()
while read -r CONTAINER_ID _; do
    [[ -n ${CONTAINER_ID} ]] && LOCAL_CONTAINERS[${CONTAINER_ID}]=1
done < <(weka cluster container -F "hostname=${HOSTNAME_SHORT}" --no-header -o id,container 2> /dev/null)

# Addresses this host actually holds, and the MAC of each device.
declare -A LOCAL_ADDR=()
while IFS= read -r LINE; do
    if [[ ${LINE} =~ ^[0-9]+:[[:space:]]+([^[:space:]@]+)[^[:space:]]*[[:space:]]+inet[[:space:]]+([^/]+)/ ]]; then
        LOCAL_ADDR["${BASH_REMATCH[1]}|${BASH_REMATCH[2]}"]=1
    fi
done < <(ip -o -4 addr show 2> /dev/null)

# Neighbour entries, keyed by address. A locally held address normally has no entry;
# one appearing here means something else on the wire answered for it.
declare -A ARP_MAC=()
while read -r NEIGH_IP _ _ FIELD4 FIELD5 _; do
    [[ ${FIELD4:-} == "lladdr" && -n ${FIELD5:-} ]] && ARP_MAC[${NEIGH_IP}]=${FIELD5,,}
done < <(ip -o -4 neigh show 2> /dev/null)

ARPING_FLAG=""
if command -v arping &> /dev/null; then
    # iputils arping takes -I for the interface; Thomas Habets' arping takes -i.
    if arping -V 2>&1 | grep -qi iputils; then
        ARPING_FLAG="-I"
    else
        ARPING_FLAG="-i"
    fi
else
    echo "INFO: arping not installed, skipping the on-the-wire duplicate check"
fi

device_mac() {
    local device=$1
    [[ -r /sys/class/net/${device}/address ]] || return 1
    local mac
    read -r mac < "/sys/class/net/${device}/address"
    printf '%s' "${mac,,}"
}

arping_mac() {
    local device=$1 address=$2 line
    while IFS= read -r line; do
        if [[ ${line} =~ ([[:xdigit:]]{2}:){5}[[:xdigit:]]{2} ]]; then
            printf '%s' "${BASH_REMATCH[0],,}"
            return 0
        fi
    done < <(arping "${ARPING_FLAG}" "${device}" -c 2 "${address}" 2> /dev/null)
    return 1
}

###############################
# LOCALLY ASSIGNED FIP CHECKS #
###############################
while read -r FIP_IP FIP_CONTAINER FIP_INTERFACE _; do
    [[ -z ${FIP_IP} || -z ${FIP_INTERFACE} ]] && continue
    [[ -n ${LOCAL_CONTAINERS[${FIP_CONTAINER}]:-} ]] || continue

    # Exact match on the address: a substring search for 10.0.0.1 also hits
    # 10.0.0.10 and the broadcast address on the same line.
    if [[ -z ${LOCAL_ADDR["${FIP_INTERFACE}|${FIP_IP}"]:-} ]]; then
        echo "WARN: Unable to locate FIP ${FIP_IP} on interface ${FIP_INTERFACE}"
        RETURN_CODE=254
        continue
    fi

    FIP_MAC=$(device_mac "${FIP_INTERFACE}") || continue
    [[ -z ${FIP_MAC} ]] && continue

    ###################
    # ARP CACHE CHECK #
    ###################
    FIP_MAC_ARP=${ARP_MAC[${FIP_IP}]:-}
    if [[ -n ${FIP_MAC_ARP} && ${FIP_MAC_ARP} != "${FIP_MAC}" ]]; then
        echo "WARN: FIP ${FIP_IP} is on ${FIP_INTERFACE} (${FIP_MAC}) but the arp cache holds ${FIP_MAC_ARP}"
        echo "      Another host may still be answering for it. A brief overlap is normal"
        echo "      immediately after a failover, so re-run before acting on this."
        RETURN_CODE=254
    fi

    ################
    # ARPING CHECK #
    ################
    if [[ -n ${ARPING_FLAG} ]]; then
        FIP_MAC_ARP=$(arping_mac "${FIP_INTERFACE}" "${FIP_IP}")
        if [[ -n ${FIP_MAC_ARP} && ${FIP_MAC_ARP} != "${FIP_MAC}" ]]; then
            echo "WARN: FIP ${FIP_IP} is on ${FIP_INTERFACE} (${FIP_MAC}), but ${FIP_MAC_ARP} answered the arping"
            RETURN_CODE=254
        fi
    fi
done < <(weka nfs interface-group assignment --no-header -o "ip,${ASSIGN_COL},port" 2> /dev/null)

##########################################
# CLUSTER STATE VS LOCAL STATE FIP TABLE #
##########################################
LEADER_PROCESS=$(weka cluster process -L --no-header -o "${PROCESS_COL}" 2> /dev/null | head -n1)
FRONTEND_PROCESS=$(weka cluster process \
    -F "hostname=${HOSTNAME_SHORT},role=FRONTEND" --no-header -o "${PROCESS_COL}" 2> /dev/null | head -n1)

declare -A GLOBAL_STATUS=() GLOBAL_SOURCE=() GLOBAL_VER=()

# The floatingIps table is an object keyed by IP: the IP keys sit at two levels of
# indent, their fields at three, and the fields of the nested serial/ver objects at
# four. Keying on that depth keeps 'value' under "ver" apart from 'value' under
# "serial", and survives the key reordering between 4.4 and 6.x.
parse_fip_table() {
    local line current_ip="" nested="" status="" source="" ver=""

    while IFS= read -r line; do
        if [[ ${line} =~ ^\ {8}\"(.+)\":\ \{$ ]]; then
            current_ip=${BASH_REMATCH[1]}
            nested=""
            status=""
            source=""
            ver=""
        elif [[ ${line} =~ ^\ {8}\},?$ ]]; then
            # One separator that is not IFS whitespace, so an empty field stays a field.
            [[ -n ${current_ip} ]] && printf "%s|%s|%s|%s\\n" "${current_ip}" "${status}" "${source}" "${ver}"
            current_ip=""
            nested=""
        elif [[ ${line} =~ ^\ {12}\"([A-Za-z0-9_]+)\":\ \{$ ]]; then
            nested=${BASH_REMATCH[1]}
        elif [[ ${line} =~ ^\ {12}\},?$ ]]; then
            nested=""
        elif [[ -n ${current_ip} && ${line} =~ ^\ {12}\"status\":\ \"?([A-Za-z_]+)\"?,?$ ]]; then
            status=${BASH_REMATCH[1]}
        elif [[ -n ${current_ip} && ${nested} == "serial" &&
                ${line} =~ ^\ {16}\"sourceNodeId\":\ \"?([^\",]+)\"?,?$ ]]; then
            source=${BASH_REMATCH[1]}
        elif [[ -n ${current_ip} && ${nested} == "ver" &&
                ${line} =~ ^\ {16}\"value\":\ ([0-9]+),?$ ]]; then
            ver=${BASH_REMATCH[1]}
        fi
    done
}

if [[ -n ${LEADER_PROCESS} ]]; then
    while IFS="|" read -r FIP_IP FIP_STATUS FIP_SOURCE FIP_VER; do
        [[ -z ${FIP_IP} ]] && continue
        GLOBAL_STATUS[${FIP_IP}]=${FIP_STATUS}
        GLOBAL_SOURCE[${FIP_IP}]=${FIP_SOURCE}
        GLOBAL_VER[${FIP_IP}]=${FIP_VER:-0}
    done < <(weka debug manhole get_aggregated_cluster_status table_names="floatingIps" \
        -n "${LEADER_PROCESS}" 2> /dev/null | parse_fip_table)

    for FIP_IP in "${!GLOBAL_VER[@]}"; do
        if (( GLOBAL_VER[${FIP_IP}] > MAX_FIP_VERSION )); then
            echo "WARN: Cluster state FIP ${FIP_IP} has a version value greater than 16k (${GLOBAL_VER[${FIP_IP}]})."
            echo "Review WEKAPP-471021 for remediation."
            RETURN_CODE=254
        fi
    done
fi

if [[ -n ${FRONTEND_PROCESS} ]]; then
    declare -A LOCAL_STATUS=()
    while IFS="|" read -r FIP_IP FIP_STATUS _ _; do
        [[ -z ${FIP_IP} ]] && continue
        LOCAL_STATUS[${FIP_IP}]=${FIP_STATUS}
    done < <(weka debug manhole get_localstate table_names="floatingIps" \
        -n "${FRONTEND_PROCESS}" 2> /dev/null | parse_fip_table)

    for FIP_IP in "${!LOCAL_STATUS[@]}"; do
        [[ ${LOCAL_STATUS[${FIP_IP}]} == "OK" ]] || continue

        # Does this host actually hold the address it believes it holds?
        FOUND=""
        for KEY in "${!LOCAL_ADDR[@]}"; do
            [[ ${KEY##*|} == "${FIP_IP}" ]] && FOUND=1 && break
        done

        if [[ -z ${FOUND} ]]; then
            echo "WARN: Local state FIP ${FIP_IP} not assigned to interface"
            RETURN_CODE=254
            continue
        fi

        # ...and does the cluster agree that this process is the one holding it?
        if [[ -z ${GLOBAL_STATUS[${FIP_IP}]:-} ]]; then
            echo "WARN: FIP ${FIP_IP} is held locally but absent from the cluster state table"
            RETURN_CODE=254
        elif [[ ${GLOBAL_SOURCE[${FIP_IP}]:-} != "NodeId<${FRONTEND_PROCESS}>" &&
                ${GLOBAL_SOURCE[${FIP_IP}]:-} != "${FRONTEND_PROCESS}" ]]; then
            echo "WARN: Global state FIP ${FIP_IP} is sourced from ${GLOBAL_SOURCE[${FIP_IP}]:-unknown},"
            echo "      but it is held locally by process ${FRONTEND_PROCESS}"
            RETURN_CODE=254
        fi
    done
fi

if [[ ${RETURN_CODE} -eq 0 ]]; then
    echo "NFSW FIPs sanity check passed."
fi

exit ${RETURN_CODE}
