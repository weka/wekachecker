#!/bin/bash

# No -e: this script inspects the exit codes of the commands it runs.
set -uo pipefail

DESCRIPTION="Check if netmask configured in container resources matches netmask on interface"
# script type is single, parallel, sequential, or parallel-compare-backends
SCRIPT_TYPE="parallel"

RETURN_CODE=0

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

# Querying a slot that holds no process can hang instead of being refused.
if command -v timeout &> /dev/null; then
    MANHOLE=(timeout 30 weka debug manhole)
else
    MANHOLE=(weka debug manhole)
fi

# What the OS has: OS_PREFIX["<device>|<address>"] is the prefix length, and every
# device the OS knows about is in OS_DEVICE even if it carries no address.
declare -A OS_PREFIX=()
declare -A OS_DEVICE=()

while IFS= read -r LINE; do
    if [[ ${LINE} =~ ^[0-9]+:[[:space:]]+([^[:space:]@]+)[^[:space:]]*[[:space:]]+inet6?[[:space:]]+([^/]+)/([0-9]+) ]]; then
        OS_DEVICE[${BASH_REMATCH[1]}]=1
        # Lower-cased because weka and iproute2 may disagree on IPv6 hex case.
        OS_PREFIX["${BASH_REMATCH[1]}|${BASH_REMATCH[2],,}"]=${BASH_REMATCH[3]}
    fi
done < <(ip -o addr show 2> /dev/null)

if [[ ${#OS_DEVICE[@]} -eq 0 ]]; then
    echo "ERROR: Not able to read interface addresses with 'ip -o addr show'."
    exit 254
fi

# 4.4 targets a container's manhole with its API port; from 6.x that is ignored and
# every query lands on the same container, so the container id has to be used.
if weka debug manhole --help 2>&1 | grep -q -- "--container"; then
    MANHOLE_BY_ID="true"
else
    MANHOLE_BY_ID="false"
fi

# Only weka containers own DPDK ports; the protocol containers (ganesha, samba, s3,
# envoy, telemetry...) do not. 6.x can filter on the container type directly; 4.4 has
# no such column, so there the known protocol container names are skipped by name.
FILTERED_BY_TYPE="true"
CONTAINERS=$(weka local ps --output name,port --filter type=weka --no-header 2> /dev/null)
if [[ -z ${CONTAINERS} ]]; then
    FILTERED_BY_TYPE="false"
    CONTAINERS=$(weka local ps --output name,port --no-header 2> /dev/null)
fi

if [[ -z ${CONTAINERS} ]]; then
    echo "ERROR: Unable to list local Weka containers."
    echo "Recommended Resolution: check that the Weka agent is running ('weka local ps')."
    exit 254
fi

# 6.x needs the container id, which only 'weka local ps -J' reports. Read the ids off
# the pretty-printed JSON by indent depth: a container's own keys sit at eight spaces,
# so the nested internalStatus.container_id (twelve spaces) is not picked up.
declare -A CONTAINER_ID=()
if [[ ${MANHOLE_BY_ID} == "true" ]]; then
    NAME=""
    ID=""
    while IFS= read -r LINE; do
        if [[ ${LINE} == "    {" ]]; then
            NAME=""
            ID=""
        elif [[ ${LINE} =~ ^\ {8}\"name\":\ \"(.*)\",?$ ]]; then
            NAME=${BASH_REMATCH[1]}
        elif [[ ${LINE} =~ ^\ {8}\"containerId\":\ ([^,]*),?$ ]]; then
            ID=${BASH_REMATCH[1]}
        fi
        if [[ -n ${NAME} && -n ${ID} ]]; then
            [[ ${ID} != "null" ]] && CONTAINER_ID[${NAME}]=${ID//\"/}
            NAME=""
            ID=""
        fi
    done < <(weka local ps -J 2> /dev/null)
fi

declare -A REPORTED=()
PORTS_SEEN=0
PORTS_IN_SLOT=0

report_mismatch() {
    local container=$1 device=$2 address=$3 weka_bits=$4 os_bits=$5
    local key="${container}|${device}|${address}"

    [[ -n ${REPORTED[${key}]:-} ]] && return
    REPORTED[${key}]=1

    echo "WARN: container ${container} device ${device} (${address}) has a netmask mismatch"
    echo "      between weka resources (${weka_bits}) and the OS (${os_bits})."
    RETURN_CODE=254
}

report_missing_device() {
    local container=$1 device=$2
    local key="${container}|${device}|-"

    [[ -n ${REPORTED[${key}]:-} ]] && return
    REPORTED[${key}]=1

    echo "WARN: container ${container} is configured on NIC ${device}, which the OS does not have."
    echo "      Review the output of 'weka local resources -C ${container}' for validity."
    RETURN_CODE=254
}

# Read one slot's port list and compare every kernel-backed port against the OS.
# Leaves the number of ports the slot reported in PORTS_IN_SLOT.
check_slot() {
    local container=$1 slot=$2
    shift 2
    local ip="" netdev="" bits="" line os_bits

    PORTS_IN_SLOT=0

    # IFS= keeps the leading whitespace that identifies the nesting depth.
    while IFS= read -r line; do
        # Each port is an object at one level of indent and its fields sit at two. A
        # JSON string never spans lines, so neither the nested l2Addr object nor the
        # embedded DPDK init logs can be mistaken for structure.
        if [[ ${line} == "    {" ]]; then
            ip=""
            netdev=""
            bits=""
            continue
        fi

        if [[ ${line} =~ ^\ {4}\},?$ ]]; then
            PORTS_IN_SLOT=$(( PORTS_IN_SLOT + 1 ))

            # A port with no kernel netdev is bound to DPDK, so the OS holds nothing
            # to compare it against.
            [[ -z ${netdev} ]] && continue

            if [[ -z ${OS_DEVICE[${netdev}]:-} ]]; then
                report_missing_device "${container}" "${netdev}"
                continue
            fi

            # Weka only shares an address with the OS in single-IP mode; otherwise
            # the address is simply not on that device and there is nothing to check.
            os_bits=${OS_PREFIX["${netdev}|${ip,,}"]:-}
            [[ -z ${os_bits} || -z ${bits} ]] && continue

            if [[ ${bits} != "${os_bits}" ]]; then
                report_mismatch "${container}" "${netdev}" "${ip}" "${bits}" "${os_bits}"
            fi
            continue
        fi

        if [[ ${line} =~ ^\ {8}\"ip\":\ \"(.*)\",?$ ]]; then
            ip=${BASH_REMATCH[1]}
        elif [[ ${line} =~ ^\ {8}\"netdevName\":\ \"(.*)\",?$ ]]; then
            netdev=${BASH_REMATCH[1]}
        elif [[ ${line} =~ ^\ {8}\"netdevName\":\ null,?$ ]]; then
            netdev=""
        elif [[ ${line} =~ ^\ {8}\"netmaskBits\":\ ([0-9]+),?$ ]]; then
            bits=${BASH_REMATCH[1]}
        fi
    done < <("${MANHOLE[@]}" -s "${slot}" network_get_dpdk_ports "$@" 2> /dev/null)

    PORTS_SEEN=$(( PORTS_SEEN + PORTS_IN_SLOT ))
}

PROTOCOL_CONTAINERS=" envoy ganesha nfsw s3 samba smb smbw telemetry dataserv "

while read -r NAME API_PORT; do
    [[ -z ${NAME} ]] && continue
    # Without a type column, an exact name match is the only way to tell a protocol
    # container apart; matching on substrings would drop names such as "s3-fe".
    if [[ ${FILTERED_BY_TYPE} == "false" && ${PROTOCOL_CONTAINERS} == *" ${NAME} "* ]]; then
        continue
    fi

    if [[ ${MANHOLE_BY_ID} == "true" ]]; then
        [[ -z ${CONTAINER_ID[${NAME}]:-} ]] && continue
        TARGET=(--container "${CONTAINER_ID[${NAME}]}")
    else
        [[ -z ${API_PORT} ]] && continue
        TARGET=(-P "${API_PORT}")
    fi

    # Slot 0 is the management node, which holds the socket-backed ports; slot 1 is
    # the container's first IO node, which holds the DPDK ports. Every IO slot of a
    # container shares one port configuration, so the first one is representative.
    for SLOT in 0 1; do
        check_slot "${NAME}" "${SLOT}" "${TARGET[@]}"
    done
done <<< "${CONTAINERS}"

if [[ ${RETURN_CODE} -ne 0 ]]; then
    echo
    echo "Recommended Resolution: determine the correct netmasks of the interfaces being used by Weka."
    echo "If Weka needs to be reconfigured, this will be done with commands like:"
    echo " weka local resources -C <WEKA-CONTAINER> net remove <NIC>"
    echo " weka local resources -C <WEKA-CONTAINER> net add    <NIC> --netmask <BIT-LENGTH> --gateway <OPTIONAL GATEWAY>"
    echo " weka local resources -C <WEKA-CONTAINER> apply"
elif (( PORTS_SEEN == 0 )); then
    echo "Unable to read network port information from any Weka container."
    echo "Recommended Resolution: check that the containers are running and that this"
    echo "account is able to run 'weka debug manhole'."
    RETURN_CODE=254
else
    echo "All Weka containers have consistent netmasks"
fi

exit ${RETURN_CODE}
