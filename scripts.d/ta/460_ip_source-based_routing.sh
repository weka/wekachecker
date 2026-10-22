#!/bin/bash

# No -e: counting a finding with (( x++ )) returns 1 when x is 0, which under
# 'set -e' killed this script the moment it detected its first problem.
set -uo pipefail

DESCRIPTION="Verify if source-based IP routing is required (and set up)"
SCRIPT_TYPE="parallel"
JIRA_REFERENCE="WEKAPP-360289"
WTA_REFERENCE=""
KB_REFERENCE=""
RETURN_CODE=0

# Last modified: 2026-10-08

if (( BASH_VERSINFO[0] < 4 )); then
    echo "ERROR: bash 4 or newer is required to run this check."
    exit 254
fi

declare -A WEKA_NICS=()
declare -A ALL_NICS=()
declare -A NETWORK_PREFIX_NICS=()
declare -A VALIDATED_NICS=()
declare -A LOCAL_IPS=()
WEKA_CONFIGURED_NICS=()

declare -A SYSCTL_KEYS=(
    ["arp_announce"]="2"
    ["arp_filter"]="1"
    ["arp_ignore"]="1"
    ["ignore_routes_with_linkdown"]="1"
)

get_network_prefix() {
    local cidr="$1"

    # IPv4 Handling
    local ip subnet mask IFS=.
    ip="${cidr%/*}"
    subnet="${cidr#*/}"
    mask=$(( (1 << subnet) - 1 << (32 - subnet) ))
    set -- $ip
    local -a octets=($1 $2 $3 $4)
    local ip_int=$(( (${octets[0]} << 24) | (${octets[1]} << 16) | (${octets[2]} << 8) | ${octets[3]} ))
    local net_int=$(( ip_int & mask ))
    local net_addr=$(( (net_int >> 24) & 255 )).$(( (net_int >> 16) & 255 )).$(( (net_int >> 8) & 255 )).$(( net_int & 255 ))
    echo "$net_addr"
}

check_sysctl() {
    local key="$1"
    local expected="$2"
    local interface="$3"

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

# Convert an IP address to a 32-bit integer
ip_to_int() {
    local IFS='.'
    read -r a b c d <<< "$1"
    echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

# Check if a given IP falls within a CIDR range
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

if ! command -v weka &> /dev/null; then
    echo "WEKA not found."
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

# Only weka containers own dataplane NICs. 6.x can filter on container type; 4.4 has
# no such column, so there the known protocol container names are skipped by name.
FILTERED_BY_TYPE="true"
CONTAINERS=$(weka local ps --output name --filter type=weka --no-header 2> /dev/null)
if [[ -z ${CONTAINERS} ]]; then
    FILTERED_BY_TYPE="false"
    CONTAINERS=$(weka local ps --output name --no-header 2> /dev/null)
fi
PROTOCOL_CONTAINERS=" envoy ganesha nfsw s3 samba smb smbw telemetry dataserv "

# Determine what NICs are being used as dataplane NICs
while read -r WEKA_CONTAINER; do
    [[ -z ${WEKA_CONTAINER} ]] && continue
    if [[ ${FILTERED_BY_TYPE} == "false" && ${PROTOCOL_CONTAINERS} == *" ${WEKA_CONTAINER} "* ]]; then
        continue
    fi

    while read -r NET_ENTRY; do
        if [[ ${NET_ENTRY} =~ "name:"(.*) ]]; then
            NET_NAME=${BASH_REMATCH[1]}
            [[ -z ${NET_NAME} ]] && continue
            WEKA_CONFIGURED_NICS+=("${NET_NAME}")
            if [[ $(ip -4 -j -o addr show dev "${NET_NAME}" 2>/dev/null | tr -d \"\[:blank:]) =~ "local:"([0-9\.]+)",prefixlen:"([0-9]+) ]]; then
                NET_IP=${BASH_REMATCH[1]}
                NETMASK=${BASH_REMATCH[2]}
                WEKA_NICS["${NET_NAME}"]="${NET_IP}/${NETMASK}"
            fi
        fi
    done < <(weka local resources -C "${WEKA_CONTAINER}" net --stable -J 2>/dev/null | grep -w -e name | tr -d \"\,[:blank:])
done <<< "${CONTAINERS}"

if [[ ${#WEKA_NICS[@]} -eq 0 ]]; then
    if [[ ${#WEKA_CONFIGURED_NICS[@]} -gt 0 ]]; then
        # Normal for a DPDK deployment: the NIC is bound to igb_uio/vfio and the
        # kernel cannot see it, so the kernel is not routing Weka data traffic and
        # source-based routing has nothing to do with it.
        printf '%s\n' "None of the Weka dataplane NICs (${WEKA_CONFIGURED_NICS[*]}) carry a kernel IPv4 address."
        echo "They are bound to a userspace (DPDK) driver, so the kernel does not route Weka"
        echo "data traffic on this host and source-based routing does not apply."
        exit 0
    fi
    echo "ERROR: Unable to determine any Weka dataplane NICs, nothing to check." >&2
    exit 254
fi

# Enumerate all (IPv4) NICs on the system
while read -r NIC_NAME NIC_VALUE; do
    ALL_NICS["${NIC_NAME}"]="${NIC_VALUE}"
done < <(ip -o -f inet addr show scope global primary | awk '{print $2, $4}')

# Every address this host holds, including secondary and non-global ones: the kernel
# routes any of them via lo, and treating one as remote produces a bogus mismatch.
while read -r LOCAL_ADDR; do
    [[ -n ${LOCAL_ADDR} ]] && LOCAL_IPS["${LOCAL_ADDR}"]=1
done < <(ip -o -f inet addr show 2>/dev/null | awk '{split($4,a,"/"); print a[1]}')

# Determine network prefix for all NICs
for NIC in "${!ALL_NICS[@]}"; do
    network_prefix=$(get_network_prefix "${ALL_NICS[$NIC]}")
    NETWORK_PREFIX_NICS["$network_prefix"]+="$NIC "
done

# Determine if any NICs' network prefix overlaps with WEKA dataplane NICs
for WEKA_NIC in "${!WEKA_NICS[@]}"; do
    network_prefix=$(get_network_prefix "${WEKA_NICS[$WEKA_NIC]}")

    NIC_LIST="${NETWORK_PREFIX_NICS[$network_prefix]:-}"
    read -r -a overlapping_nics <<< "$NIC_LIST"

    if (( ${#overlapping_nics[@]} > 1 )); then
        for OVERLAP_NIC in "${overlapping_nics[@]}"; do
            if [[ -z ${VALIDATED_NICS[$OVERLAP_NIC]:-} ]]; then
                VALIDATED_NICS["$OVERLAP_NIC"]=1

                # Validate all sysctl keys
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
                else
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
                fi
            fi
        done
    fi
done

IP_ROUTE_GET_ERRORS=0

# A container may list several addresses in one field; splitting on the comma keeps
# them as separate addresses instead of fusing them into one invalid one.
DESTINATIONS=$(weka cluster container --backends --output ips --no-header 2>/dev/null \
    | tr ',' '\n' | awk 'NF' | sort -u)

if [[ -z "${DESTINATIONS}" ]]; then
    echo "ERROR: No destination IPs retrieved from weka command." >&2
    exit 254 # exit early... not much else we can do
fi

for IFACE in "${!WEKA_NICS[@]}"; do
    CIDR="${WEKA_NICS[${IFACE}]}"
    LOCAL_IP="${CIDR%%/*}"

    if ! nic_is_up "${IFACE}"; then
        echo "SKIP: ${IFACE} (${LOCAL_IP}) is down, skipping."
        continue
    fi

    for DEST in ${DESTINATIONS}; do
        # Skip destinations outside this interface's subnet
        if ! ip_in_cidr "${DEST}" "${CIDR}"; then
            continue
        fi

        ROUTE_OUTPUT=$(ip route get "${DEST}" from "${LOCAL_IP}" 2>&1) || {
            echo "WARN: 'ip route get ${DEST} from ${LOCAL_IP}' failed: ${ROUTE_OUTPUT}" >&2
            continue
        }

        ACTUAL_IFACE=$(awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' <<< "${ROUTE_OUTPUT}" | head -1)

        if [[ -z "${ACTUAL_IFACE}" ]]; then
            echo "WARN: Could not parse dev from route output for ${LOCAL_IP} -> ${DEST}" >&2
            echo "      Output was: ${ROUTE_OUTPUT}" >&2
            IP_ROUTE_GET_ERRORS=$(( IP_ROUTE_GET_ERRORS + 1 ))
            continue
        fi

        # If the destination is one of our local IPs, kernel routes via lo -- that's expected
        if [[ -n "${LOCAL_IPS[${DEST}]:-}" ]]; then
            if [[ "${ACTUAL_IFACE}" != "lo" ]]; then
                echo "MISMATCH: ${LOCAL_IP} -> ${DEST} is local but routed via '${ACTUAL_IFACE}' instead of lo"
                echo "          Full output: ${ROUTE_OUTPUT}"
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

echo ""
if (( IP_ROUTE_GET_ERRORS > 0 )); then
    echo "Failure evaluating the output of ip route get - RESULT: ${IP_ROUTE_GET_ERRORS} issue(s) detected."
    RETURN_CODE=254
else
    echo "RESULT: All routes use the expected outgoing interface."
fi

if [[ $RETURN_CODE -eq 0 ]]; then
    echo "Source-based routing is not required or is correct."
else
    echo "Recommended Resolution: review the required network settings from the WEKA docs:"
    echo "https://docs.weka.io/planning-and-installation/bare-metal/setting-up-the-hosts#configure-the-networking"
fi

exit "$RETURN_CODE"
