#!/bin/bash

# No -e: this script inspects the exit codes of the commands it runs.
set -uo pipefail

DESCRIPTION="Check DNS configuration"
SCRIPT_TYPE="parallel"

RETURN_CODE=0
RESOLV_CONF="/etc/resolv.conf"
PHONE_HOME="home.weka.io"
QUERY_TIMEOUT=2

# Every nameserver in resolv.conf, not just the first: a resolver that does not
# answer stalls every lookup behind it until it times out, so one bad entry out of
# three still hurts. ';' and '#' both start a comment in resolv.conf.
NAMESERVERS=()
# glibc defaults, overridden by an "options" line; they set how long a dead server
# ahead of a live one stalls each lookup.
RESOLV_TIMEOUT=5
RESOLV_ROTATE="no"
if [[ -r ${RESOLV_CONF} ]]; then
    while IFS= read -r LINE || [[ -n ${LINE} ]]; do
        LINE=${LINE%%#*}
        LINE=${LINE%%;*}
        read -r KEYWORD VALUE _ <<< "${LINE}"
        if [[ ${KEYWORD:-} == "nameserver" && -n ${VALUE:-} ]]; then
            NAMESERVERS+=("${VALUE}")
        elif [[ ${KEYWORD:-} == "options" ]]; then
            for OPTION in ${LINE}; do
                case ${OPTION} in
                    timeout:*) RESOLV_TIMEOUT=${OPTION#timeout:} ;;
                    rotate)    RESOLV_ROTATE="yes" ;;
                esac
            done
        fi
    done < "${RESOLV_CONF}"
else
    echo "WARN: ${RESOLV_CONF} is missing or unreadable."
    echo "Recommended Resolution: configure at least one working nameserver."
    exit 254
fi

if [[ ${#NAMESERVERS[@]} -eq 0 ]]; then
    echo "WARN: no nameserver entries found in ${RESOLV_CONF}."
    echo "Name resolution will fall back to ${HOSTALIASES:-/etc/hosts} only, which will break"
    echo "anything that resolves cluster or object-store hostnames."
    echo "Recommended Resolution: configure at least one working nameserver."
    exit 254
fi

echo "Found ${#NAMESERVERS[@]} DNS server(s) in ${RESOLV_CONF}: ${NAMESERVERS[*]}"

if command -v dig &> /dev/null; then
    DNS_TOOL="dig"
elif command -v host &> /dev/null; then
    DNS_TOOL="host"
elif command -v nslookup &> /dev/null; then
    DNS_TOOL="nslookup"
else
    echo "Could not find a DNS lookup utility, please install one with"
    echo " yum -y install bind-utils   (or)   apt-get install dnsutils"
    exit 254
fi

# The name used to probe a server. Resolving it is not required -- an NXDOMAIN is a
# perfectly good answer -- it only has to make the server say something.
PROBE_NAME=$(hostname -f 2> /dev/null)
[[ -z ${PROBE_NAME} ]] && PROBE_NAME=$(hostname 2> /dev/null)
[[ -z ${PROBE_NAME} ]] && PROBE_NAME="${PHONE_HOME}"

# True when the server answered at all. Exit codes cannot be used for this: 'host'
# and 'nslookup' both return 1 for NXDOMAIN (an answer) and for an unreachable
# server (not an answer), so the transport error has to be read off the output.
server_responded() {
    local server=$1 output rc

    case ${DNS_TOOL} in
        dig)
            output=$(dig +time="${QUERY_TIMEOUT}" +tries=1 "@${server}" "${PROBE_NAME}" 2>&1)
            rc=$?
            # 9 is dig's dedicated "no servers could be reached".
            (( rc == 9 )) && return 1
            ;;
        host)
            output=$(host -W "${QUERY_TIMEOUT}" "${PROBE_NAME}" "${server}" 2>&1)
            ;;
        nslookup)
            output=$(nslookup "-timeout=${QUERY_TIMEOUT}" "${PROBE_NAME}" "${server}" 2>&1)
            ;;
    esac

    if [[ ${output} == *"no servers could be reached"* ||
          ${output} == *"connection timed out"* ||
          ${output} == *"communications error"* ||
          ${output} == *"no response from server"* ||
          ${output} == *"Host or domain name not found"*"timed out"* ]]; then
        return 1
    fi

    return 0
}

# True when the name resolves to an address through the default resolver order.
name_resolves() {
    local name=$1

    case ${DNS_TOOL} in
        dig)
            [[ -n $(dig +short +time="${QUERY_TIMEOUT}" +tries=1 A "${name}" 2> /dev/null) ]]
            ;;
        host)
            host -W "${QUERY_TIMEOUT}" -t A "${name}" &> /dev/null
            ;;
        nslookup)
            nslookup "-timeout=${QUERY_TIMEOUT}" "${name}" 2> /dev/null \
                | sed -n '/^Name:/,$p' | grep -q "^Address"
            ;;
    esac
}

# The resolver walks resolv.conf in order, so where a dead server sits in the list
# decides what it costs: ahead of the first working one it delays every single
# lookup, behind it only removes a fallback.
DEAD_SERVERS=()
PREFERRED_DEAD=()
TRAILING_DEAD=()
FIRST_LIVE=""

for INDEX in "${!NAMESERVERS[@]}"; do
    SERVER=${NAMESERVERS[${INDEX}]}
    if server_responded "${SERVER}"; then
        echo "DNS server ${SERVER} (preference $(( INDEX + 1 ))) is operational and reachable"
        [[ -z ${FIRST_LIVE} ]] && FIRST_LIVE=${INDEX}
    else
        DEAD_SERVERS+=("${SERVER}")
        if [[ -z ${FIRST_LIVE} ]]; then
            PREFERRED_DEAD+=("${SERVER}")
        else
            TRAILING_DEAD+=("${SERVER}")
        fi
    fi
done

if [[ ${#DEAD_SERVERS[@]} -eq ${#NAMESERVERS[@]} ]]; then
    echo "None of the DNS servers in ${RESOLV_CONF} answered: ${DEAD_SERVERS[*]}"
    echo "Name resolution is broken on this host, which will affect mounts, object-store"
    echo "access and cluster hostname lookups."
    echo "Recommended Resolution: correct the nameserver entries, or open udp/tcp 53 to them."
    RETURN_CODE=1
else
    if [[ ${#PREFERRED_DEAD[@]} -gt 0 ]]; then
        echo "WARN: ${#PREFERRED_DEAD[@]} of ${#NAMESERVERS[@]} DNS servers ahead of the first working one did not answer: ${PREFERRED_DEAD[*]}"
        if [[ ${RESOLV_ROTATE} == "yes" ]]; then
            echo "      'options rotate' is set, so the resolver round-robins and a share of lookups"
            echo "      waits ~${RESOLV_TIMEOUT}s on a dead server before falling through to ${NAMESERVERS[${FIRST_LIVE}]}."
        else
            echo "      ${RESOLV_CONF} is consulted in order, so EVERY lookup on this host waits about"
            echo "      $(( ${#PREFERRED_DEAD[@]} * RESOLV_TIMEOUT ))s before reaching ${NAMESERVERS[${FIRST_LIVE}]} -- a delay that lands on"
            echo "      mounts, object-store access and cluster hostname lookups."
        fi
        echo " Recommended Resolution: repair these servers, or list a working one first in ${RESOLV_CONF}."
        RETURN_CODE=254
    fi

    if [[ ${#TRAILING_DEAD[@]} -gt 0 ]]; then
        echo "WARN: ${#TRAILING_DEAD[@]} lower-preference DNS server(s) did not answer: ${TRAILING_DEAD[*]}"
        echo "      Lookups are not delayed today because ${NAMESERVERS[${FIRST_LIVE}]} answers first, but"
        echo "      these are not usable as a fallback if it stops responding."
        echo " Recommended Resolution: remove or repair the unresponsive nameserver entries."
        RETURN_CODE=254
    fi
fi

# Phone-home needs this name to resolve; it is expected to fail in air-gapped sites.
if [[ ${RETURN_CODE} -ne 1 ]] && ! name_resolves "${PHONE_HOME}"; then
    echo "WARN: ${PHONE_HOME} is not resolvable; phone-home may not be possible."
    echo "Recommended Resolution: verify this is intended; in an air-gapped deployment it is."
    RETURN_CODE=254
fi

if [[ ${RETURN_CODE} -eq 0 ]]; then
    echo "All tests passed."
fi

exit ${RETURN_CODE}
