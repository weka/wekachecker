#!/bin/bash

# No -e: counting a finding with (( x++ )) returns 1 when x is 0, which under
# 'set -e' would kill the script on its first detected problem.
set -uo pipefail

DESCRIPTION="Verify if source-based IP routing is required (and set up)"
SCRIPT_TYPE="parallel"
JIRA_REFERENCE="WEKAPP-360289"
WTA_REFERENCE=""
KB_REFERENCE=""
RETURN_CODE=0

# Last modified: 2026-09-10
# k8s-client variant: does not use the weka CLI. Every NIC with a global IPv4
# address is a candidate; backend IPs/hostnames given on the command line are
# used as route-check destinations. Without them the route check is skipped.

if (( BASH_VERSINFO[0] < 4 )); then
    echo "ERROR: bash 4 or newer is required to run this check."
    exit 254
fi

declare -A ALL_NICS=()
declare -A NETWORK_PREFIX_NICS=()
declare -A VALIDATED_NICS=()

declare -A SYSCTL_KEYS=(
    ["arp_announce"]="2"
    ["arp_filter"]="1"
    ["arp_ignore"]="1"
    ["ignore_routes_with_linkdown"]="1"
)

get_network_prefix() {
    local cidr="$1"
    local ip subnet mask IFS=.
    ip="${cidr%/*}"
    subnet="${cidr#*/}"
    mask=$(( (1 << subnet) - 1 << (32 - subnet) ))
    set -- $ip
    local -a octets=($1 $2 $3 $4)
    local ip_int=$(( (${octets[0]} << 24) | (${octets[1]} << 16) | (${octets[2]} << 8) | ${octets[3]} ))
    local net_int=$(( ip_int & mask ))
    echo $(( (net_int >> 24) & 255 )).$(( (net_int >> 16) & 255 )).$(( (net_int >> 8) & 255 )).$(( net_int & 255 ))
}

check_sysctl() {
    local key="$1" expected="$2" interface="$3"
    local all_val iface_val
    all_val=$(sysctl -n "net/ipv4/conf/all/${key}" 2>/dev/null)
    iface_val=$(sysctl -n "net/ipv4/conf/${interface}/${key}" 2>/dev/null)
    if [[ "$all_val" == "$expected" ]]; then
        echo "$all_val"
    elif [[ "$iface_val" == "$expected" ]]; then
        echo "$iface_val"
    else
        echo ""
    fi
}

ip_to_int() {
    local IFS='.'
    read -r a b c d <<< "$1"
    echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

ip_in_cidr() {
    local ip_int cidr_ip cidr_bits cidr_ip_int mask
    ip_int=$(ip_to_int "$1")
    cidr_ip="${2%%/*}"
    cidr_bits="${2##*/}"
    cidr_ip_int=$(ip_to_int "${cidr_ip}")
    mask=$(( 0xFFFFFFFF << (32 - cidr_bits) & 0xFFFFFFFF ))
    (( (ip_int & mask) == (cidr_ip_int & mask) ))
}

# Name of the routing table an 'ip rule' selects for a source address, or nothing
# when no rule matches. Table names may contain '-' and '.', which \w does not match.
rule_table_for() {
    local ip="$1" escaped line
    escaped=${ip//./\\.}

    while IFS= read -r line; do
        [[ ${line} =~ from[[:space:]]+${escaped}(/32)?[[:space:]] ]] || continue
        if [[ ${line} =~ lookup[[:space:]]+([^[:space:]]+) ]]; then
            printf '%s' "${BASH_REMATCH[1]}"
            return 0
        fi
    done < <(ip rule 2>/dev/null)

    return 1
}

# IPoIB links and some bonds sit in operstate 'unknown' while perfectly usable, so
# only an explicit 'down' is treated as a reason to skip the interface.
nic_is_up() {
    local dev="$1" state
    [[ -r /sys/class/net/${dev}/operstate ]] || return 0
    read -r state < "/sys/class/net/${dev}/operstate"
    [[ ${state} != "down" ]]
}

# Enumerate all (IPv4) NICs on the system
while read -r NIC_NAME NIC_VALUE; do
    ALL_NICS["${NIC_NAME}"]="${NIC_VALUE}"
done < <(ip -o -f inet addr show scope global primary | awk '{print $2, $4}')

if [[ ${#ALL_NICS[@]} -eq 0 ]]; then
    echo "No NICs with global IPv4 addresses found, nothing to check."
    exit 0
fi

# Group NICs by network prefix
for NIC in "${!ALL_NICS[@]}"; do
    network_prefix=$(get_network_prefix "${ALL_NICS[$NIC]}")
    NETWORK_PREFIX_NICS["$network_prefix"]+="$NIC "
done

# Any prefix shared by more than one NIC requires source-based routing
for network_prefix in "${!NETWORK_PREFIX_NICS[@]}"; do
    read -r -a overlapping_nics <<< "${NETWORK_PREFIX_NICS[$network_prefix]:-}"
    if (( ${#overlapping_nics[@]} <= 1 )); then
        continue
    fi
    for OVERLAP_NIC in "${overlapping_nics[@]}"; do
        if [[ -n ${VALIDATED_NICS[$OVERLAP_NIC]:-} ]]; then
            continue
        fi
        VALIDATED_NICS["$OVERLAP_NIC"]=1

        for key in "${!SYSCTL_KEYS[@]}"; do
            SYSCTL_VALUE=$(check_sysctl "$key" "${SYSCTL_KEYS[$key]}" "$OVERLAP_NIC")
            if [[ "$SYSCTL_VALUE" != "${SYSCTL_KEYS[$key]}" ]]; then
                RETURN_CODE=254
                echo "WARNING: $key is not set to ${SYSCTL_KEYS[$key]} on interface $OVERLAP_NIC"
            fi
        done

        LOCAL_ROUTE_ENTRY_FOUND=0
        DEFAULT_ROUTE_ENTRY_FOUND=0
        IFS=/ read -r NIC_IP NIC_MASK <<< "${ALL_NICS[$OVERLAP_NIC]}"

        ROUTE_TABLE=$(rule_table_for "$NIC_IP")
        if [[ -z "$ROUTE_TABLE" ]]; then
            RETURN_CODE=254
            echo "WARNING: No ip rule found for IP $NIC_IP (interface $OVERLAP_NIC shares subnet $network_prefix/$NIC_MASK with another NIC)"
            continue
        fi

        while read -r ROUTE_ENTRY; do
            re="^${network_prefix}/${NIC_MASK}[[:space:]]+dev[[:space:]]+${OVERLAP_NIC}.*[[:space:]]src[[:space:]]${NIC_IP}"
            if [[ $ROUTE_ENTRY =~ $re ]]; then
                LOCAL_ROUTE_ENTRY_FOUND=1
            elif [[ $ROUTE_ENTRY =~ ^default ]]; then
                DEFAULT_ROUTE_ENTRY_FOUND=1
            fi
        done < <(ip route show table "$ROUTE_TABLE" 2>/dev/null)

        if [[ $LOCAL_ROUTE_ENTRY_FOUND == 0 ]]; then
            RETURN_CODE=254
            echo "WARNING: Local route entry not found in table $ROUTE_TABLE for $OVERLAP_NIC"
        fi
        if [[ $DEFAULT_ROUTE_ENTRY_FOUND == 0 ]]; then
            RETURN_CODE=254
            echo "WARNING: default route entry not found in table $ROUTE_TABLE for $OVERLAP_NIC"
        fi
    done
done

# Destination route check: backend IPs/hostnames from the command line
DESTINATIONS=""
for HOST in "$@"; do
    DEST_IP=$(getent ahostsv4 "$HOST" 2>/dev/null | awk '{print $1; exit}')
    if [[ -n "$DEST_IP" ]]; then
        DESTINATIONS+="$DEST_IP "
    else
        echo "WARN: Unable to resolve $HOST, skipping it as a route destination"
    fi
done

IP_ROUTE_GET_ERRORS=0
if [[ -z "${DESTINATIONS// /}" ]]; then
    echo "No backend IPs given on the command line, skipping outgoing-interface route check."
else
    declare -A LOCAL_IPS=()
    for IFACE in "${!ALL_NICS[@]}"; do
        LOCAL_IPS["${ALL_NICS[${IFACE}]%%/*}"]=1
    done

    for IFACE in "${!ALL_NICS[@]}"; do
        CIDR="${ALL_NICS[${IFACE}]}"
        LOCAL_IP="${CIDR%%/*}"
        if ! nic_is_up "${IFACE}"; then
            continue
        fi
        for DEST in ${DESTINATIONS}; do
            if ! ip_in_cidr "${DEST}" "${CIDR}"; then
                continue
            fi
            ROUTE_OUTPUT=$(ip route get "${DEST}" from "${LOCAL_IP}" 2>&1) || {
                echo "WARN: 'ip route get ${DEST} from ${LOCAL_IP}' failed: ${ROUTE_OUTPUT}"
                continue
            }
            ACTUAL_IFACE=$(awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' <<< "${ROUTE_OUTPUT}" | head -1)
            if [[ -z "${ACTUAL_IFACE}" ]]; then
                echo "WARN: Could not parse dev from route output for ${LOCAL_IP} -> ${DEST}: ${ROUTE_OUTPUT}"
                IP_ROUTE_GET_ERRORS=$(( IP_ROUTE_GET_ERRORS + 1 ))
                continue
            fi
            if [[ -n "${LOCAL_IPS[${DEST}]:-}" ]]; then
                if [[ "${ACTUAL_IFACE}" != "lo" ]]; then
                    echo "MISMATCH: ${LOCAL_IP} -> ${DEST} is local but routed via '${ACTUAL_IFACE}' instead of lo"
                    IP_ROUTE_GET_ERRORS=$(( IP_ROUTE_GET_ERRORS + 1 ))
                fi
                continue
            fi
            if [[ "${ACTUAL_IFACE}" != "${IFACE}" ]]; then
                echo "MISMATCH: ${LOCAL_IP} belongs to '${IFACE}' but route to ${DEST} uses '${ACTUAL_IFACE}'"
                echo "          Full output: ${ROUTE_OUTPUT}"
                IP_ROUTE_GET_ERRORS=$(( IP_ROUTE_GET_ERRORS + 1 ))
            fi
        done
    done

    if [[ ${IP_ROUTE_GET_ERRORS} -gt 0 ]]; then
        echo "Route check: ${IP_ROUTE_GET_ERRORS} issue(s) detected."
        RETURN_CODE=254
    else
        echo "Route check: all routes use the expected outgoing interface."
    fi
fi

if [[ $RETURN_CODE -eq 0 ]]; then
    echo "Source-based routing is not required or is correct."
else
    echo "Recommended Resolution: review the required network settings from the WEKA docs:"
    echo "https://docs.weka.io/planning-and-installation/bare-metal/setting-up-the-hosts#configure-the-networking"
fi

exit "$RETURN_CODE"
