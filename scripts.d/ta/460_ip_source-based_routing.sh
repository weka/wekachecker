#!/bin/bash

set -eo pipefail # Fail with an error code if there's any sub-command/variable error

DESCRIPTION="Verify if source-based IP routing is required (and set up)"
SCRIPT_TYPE="parallel"
JIRA_REFERENCE="WEKAPP-360289"
WTA_REFERENCE=""
KB_REFERENCE=""
RETURN_CODE=0

declare -A WEKA_NICS
declare -A ALL_NICS
declare -A NETWORK_PREFIX_NICS
declare -A VALIDATED_NICS

declare -A SYSCTL_KEYS=(
    ["arp_announce"]="2"
    ["arp_filter"]="1"
    ["arp_ignore"]="1"
    ["ignore_routes_with_linkdown"]="1"
)

# Last modified: 2026-01-15

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

    all_val=$(sysctl -n "net.ipv4.conf.all.$key" 2>/dev/null)
    iface_val=$(sysctl -n "net.ipv4.conf.$interface.$key" 2>/dev/null)

    if [[ "$all_val" == "$expected" ]]; then
        echo "$all_val"
    elif [[ "$iface_val" == "$expected" ]]; then
        echo "$iface_val"
    else
        echo ""
    fi
}

# Determine what NICs are being used as dataplane NICs
while read -r WEKA_CONTAINER; do
    while read NET_ENTRY; do
        if [[ ${NET_ENTRY} =~ "name:"(.*) ]]; then
            NET_NAME=${BASH_REMATCH[1]}
            if [[ $(ip -4 -j -o addr show dev ${NET_NAME} 2>/dev/null | tr -d \"\[:blank:]) =~ "local:"([0-9\.]+)",prefixlen:"([0-9]+) ]]; then
                NET_IP=${BASH_REMATCH[1]}
                NETMASK=${BASH_REMATCH[2]}
                WEKA_NICS["${NET_NAME}"]="${NET_IP}/${NETMASK}"
            fi
        fi
    done < <(weka local resources -C "${WEKA_CONTAINER}" net --stable -J | grep -w -e name | tr -d \"\,[:blank:])
done < <(weka local ps --output name --no-header | grep -e compute -e drive -e frontend)

# Enumerate all (IPv4) NICs on the system
while read -r NIC_NAME NIC_VALUE; do
    ALL_NICS["${NIC_NAME}"]="${NIC_VALUE}"
done < <(ip -o -f inet addr show scope global primary | awk '{print $2, $4}')

# Determine network prefix for all NICs
for NIC in "${!ALL_NICS[@]}"; do
    network_prefix=$(get_network_prefix "${ALL_NICS[$NIC]}")
    NETWORK_PREFIX_NICS["$network_prefix"]+="$NIC "
done

# Determine if any NICs' network prefix overlaps with WEKA dataplane NICs
for WEKA_NIC in "${!WEKA_NICS[@]}"; do
    network_prefix=$(get_network_prefix "${WEKA_NICS[$WEKA_NIC]}")

    NIC_LIST="${NETWORK_PREFIX_NICS[$network_prefix]}"
    read -r -a overlapping_nics <<< "$NIC_LIST"

    if (( ${#overlapping_nics[@]} > 1 )); then
        for OVERLAP_NIC in "${overlapping_nics[@]}"; do
            if [[ ! -v VALIDATED_NICS["$OVERLAP_NIC"] ]]; then
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

                if ! ip rule | grep -w -q -m 1 -F "$NIC_IP" && \
                   ! ip rule | grep -w -q -m 1 -F "$NIC_IP/32"; then
                    RETURN_CODE=254
                    echo "WARNING: No ip rule found for IP $NIC_IP"
                else
                    ROUTE_TABLE=$(ip rule | grep -w -m 1 -F "$NIC_IP" | sed -r 's/.*lookup *(\w+).*/\1/')
                    if [[ -z "$ROUTE_TABLE" ]]; then
                        ROUTE_TABLE=$(ip rule | grep -w -m 1 -F "$NIC_IP/32" | sed -r 's/.*lookup *(\w+).*/\1/')
                    fi

                    if [[ -z "$ROUTE_TABLE" ]]; then
                        RETURN_CODE=254
                        echo "Route table $ROUTE_TABLE not found."
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
                            echo "WARNING: Local route entry not found in table $ROUTE_TABLE"
                        fi

                        if [[ $DEFAULT_ROUTE_ENTRY_FOUND == 0 ]]; then
                            RETURN_CODE=254
                            echo "WARNING: default route entry not found in table $ROUTE_TABLE"
                        fi
                    fi
                fi
            fi
        done
    fi
done

if [[ $RETURN_CODE -eq 0 ]]; then
    echo "Source-based routing is not required or is correct."
else
    echo "Recommended Resolution: review the required network settings from the WEKA docs:"
    echo "https://docs.weka.io/planning-and-installation/bare-metal/setting-up-the-hosts#configure-the-networking"
fi

exit "$RETURN_CODE"
