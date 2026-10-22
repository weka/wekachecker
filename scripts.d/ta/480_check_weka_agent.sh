#!/bin/bash

# No -e: this script inspects the exit codes of the commands it runs.
set -uo pipefail

DESCRIPTION="Check the weka agent is enabled"
SCRIPT_TYPE="parallel"
JIRA_REFERENCE=""
WTA_REFERENCE=""
KB_REFERENCE="SFDC 12492"
RETURN_CODE=0

AGENT_SERVICE="weka-agent"
AGENT_PID_FILE="/var/run/weka-agent.pid"
AGENT_CMDLINE="/usr/bin/weka --agent"

AGENT_ENABLED="unknown"
EXPECTED_PID=""
PID_SOURCE=""
AGENT_PIDS=()

if command -v systemctl &> /dev/null; then
    if systemctl is-enabled "${AGENT_SERVICE}" &> /dev/null; then
        AGENT_ENABLED="yes"
    else
        AGENT_ENABLED="no"
    fi
fi

if [[ ${AGENT_ENABLED} == "no" ]]; then
    echo "WARN: The service ${AGENT_SERVICE} is not reported as enabled by systemd"
    echo "This may cause weka to fail to start"
    echo " Recommended Resolution: enable the service with systemctl enable ${AGENT_SERVICE}"
    RETURN_CODE=254

    if [[ ! -L /etc/init.d ]]; then
        echo "/etc/init.d is expected to be a symlink to /etc/rc.d/init.d"
        echo "Without this systemd is unable to find and thus start the weka-agent sysV init script"
        echo " Recommended Resolution: on RHEL-based OSes move any scripts to /etc/rc.d/init.d, remove"
        echo " the /etc/init.d directory, and re-create it as a link. The following commands are"
        echo " one way to achieve this"
        echo " mv /etc/init.d/* /etc/rc.d/init.d/ && rmdir /etc/init.d && ln -s /etc/rc.d/init.d /etc/init.d"
    fi
fi

while read -r PID; do
    [[ -n ${PID} ]] && AGENT_PIDS+=("${PID}")
done < <(pgrep -x -f "${AGENT_CMDLINE}" 2> /dev/null)

# The agent runs as a systemd Type=simple service and writes no pid file, so the pid
# file is only consulted where one actually exists; otherwise systemd's own MainPID
# is the reference. With neither there is nothing to compare against, and claiming a
# mismatch would be inventing a fault.
if [[ -r ${AGENT_PID_FILE} ]]; then
    read -r EXPECTED_PID < "${AGENT_PID_FILE}"
    PID_SOURCE="${AGENT_PID_FILE}"
elif [[ ${AGENT_ENABLED} != "unknown" ]]; then
    while IFS= read -r LINE; do
        [[ ${LINE} == MainPID=* ]] && EXPECTED_PID=${LINE#MainPID=}
    done < <(systemctl show "${AGENT_SERVICE}" -p MainPID 2> /dev/null)
    [[ ${EXPECTED_PID} == "0" ]] && EXPECTED_PID=""
    PID_SOURCE="systemd MainPID"
fi

if [[ ${#AGENT_PIDS[@]} -gt 1 ]]; then
    echo "WARN: ${AGENT_SERVICE} is running ${#AGENT_PIDS[@]} times (pids ${AGENT_PIDS[*]})"
    if [[ -n ${EXPECTED_PID} ]]; then
        echo " Recommended Resolution: ensure only 1 ${AGENT_SERVICE} is running and the"
        echo "  pid matches the one in ${PID_SOURCE} (${EXPECTED_PID})"
    else
        echo " Recommended Resolution: ensure only 1 ${AGENT_SERVICE} is running"
    fi
    RETURN_CODE=254

elif [[ ${#AGENT_PIDS[@]} -eq 0 ]]; then
    # Only worth reporting when the service is supposed to be up; when it is not
    # enabled, the warning above already says so.
    if [[ ${AGENT_ENABLED} != "no" ]]; then
        echo "WARN: no '${AGENT_CMDLINE}' process is running"
        if [[ ${AGENT_ENABLED} == "unknown" ]]; then
            echo " Recommended Resolution: start the weka agent"
        else
            echo " Recommended Resolution: start the agent with systemctl start ${AGENT_SERVICE}"
        fi
        RETURN_CODE=254
    fi

elif [[ -n ${EXPECTED_PID} && ${AGENT_PIDS[0]} != "${EXPECTED_PID}" ]]; then
    echo "WARN: the ${AGENT_SERVICE} pid (${AGENT_PIDS[0]}) does not match ${PID_SOURCE} (${EXPECTED_PID})"
    echo " Recommended Resolution: ensure the pid match to prevent complications during upgrade"
    RETURN_CODE=254
fi

if [[ ${RETURN_CODE} -eq 0 ]]; then
    if [[ ${AGENT_ENABLED} == "unknown" ]]; then
        echo "${AGENT_SERVICE} is running (systemd not present, enablement not checked)"
    else
        echo "${AGENT_SERVICE} is enabled"
    fi
fi

exit ${RETURN_CODE}
