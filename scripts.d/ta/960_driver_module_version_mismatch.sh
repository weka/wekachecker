#!/bin/bash

set -u # Fail with an error code if there's any variable error

DESCRIPTION="Check the loaded wekafsio/wekafsgw kernel modules match the WEKA version the compute, drive and frontend containers run"
# script type is single, parallel, sequential, or parallel-compare-backends
SCRIPT_TYPE="parallel"
JIRA_REFERENCE=""
WTA_REFERENCE=""
KB_REFERENCE=""

# The upgrade's mount-preserving hot swap replaces only wekafsio and keeps the
# old wekafsgw loaded whenever a wekafs filesystem is mounted on the host outside
# the WEKA containers. 6.1 S3 needs a 6.1 gateway (IOCTL_RNDR), so a kept old
# gateway makes new-prefix PUTs fail with EOPNOTSUPP.

RETURN_CODE=0

if ! command -v weka &> /dev/null; then
    echo "WEKA not found."
    exit 254
fi

# Only the compute/drive/frontend containers are in scope; helper containers
# (envoy, taskmon, ...) carry versions unrelated to the driver.
# versionName, not version: 4.4 has no "version" column; 6.x accepts both.
RUNNING_VERSIONS=$(weka local ps --output name,versionName --no-header 2>/dev/null | awk '$1 ~ /compute|drive|frontend/ && NF >= 2 {print $2}' | sort -u)

if [[ -z ${RUNNING_VERSIONS} ]]; then
    echo "No compute, drive or frontend containers on this host, skipping."
    exit 0
fi
if [[ $(printf '%s\n' "${RUNNING_VERSIONS}" | wc -l) -gt 1 ]]; then
    echo "WARN: The compute, drive and frontend containers on this host run different versions ($(echo ${RUNNING_VERSIONS})) -- upgrade in progress?"
    echo "Re-run this check once every compute, drive and frontend container on the host runs the same version."
    exit 254
fi
RUNNING_VERSION=${RUNNING_VERSIONS}

if [[ ! -r /sys/module/wekafsio/version || ! -r /sys/module/wekafsgw/version ]]; then
    echo "WARN: The wekafsio/wekafsgw kernel modules are not loaded although compute, drive or frontend containers run on this host."
    exit 254
fi
LOADED_IO=$(< /sys/module/wekafsio/version)
LOADED_GW=$(< /sys/module/wekafsgw/version)

# wekafsio: the release spec names the exact module version it ships.
SPEC="/opt/weka/dist/release/${RUNNING_VERSION}.spec"
EXPECTED_IO=""
if [[ -r ${SPEC} ]]; then
    # Specs come both pretty-printed and minified onto one line; strip whitespace to match either.
    EXPECTED_IO=$(tr -d ' \t\r\n' < "${SPEC}" | grep -o '"wekafsio":{"module_version":"[0-9a-f]*"' | head -n1 | cut -d'"' -f6)
fi

if [[ -z ${EXPECTED_IO} ]]; then
    echo "WARN: Could not read the expected wekafsio version for ${RUNNING_VERSION} from ${SPEC}."
    RETURN_CODE=254
elif [[ ${LOADED_IO} != "${EXPECTED_IO}" ]]; then
    echo "WARN: Loaded wekafsio ${LOADED_IO} does not match ${EXPECTED_IO}, the module shipped with ${RUNNING_VERSION}."
    RETURN_CODE=254
fi

# wekafsgw: the spec leaves its version null, so compare against the module the
# running version installed on disk for this kernel.
INSTALLED_GW=$(modinfo -F version wekafsgw 2>/dev/null)
if [[ -z ${INSTALLED_GW} ]]; then
    echo "WARN: Could not read the installed wekafsgw version (modinfo wekafsgw) for kernel $(uname -r)."
    RETURN_CODE=254
elif [[ ${LOADED_GW} != "${INSTALLED_GW}" ]]; then
    echo "WARN: Loaded wekafsgw ${LOADED_GW} does not match the installed wekafsgw ${INSTALLED_GW} for ${RUNNING_VERSION}."
    echo "The gateway module was not reloaded during the upgrade; features that need the newer gateway fail on this host"
    echo "(on 6.1, S3 PUTs that create a new prefix fail with 'operation not supported')."
    HOST_MOUNTS=$(awk '$3 == "wekafs" {printf "%s on %s, ", $1, $2}' /proc/1/mounts)
    if [[ -n ${HOST_MOUNTS} ]]; then
        echo "wekafs mounts outside the WEKA containers, which keep the gateway loaded across an upgrade: ${HOST_MOUNTS%, }"
    fi
    echo "Recommended resolution: unmount those filesystems, then restart all WEKA containers on this host (or reboot) so the driver fully reloads."
    RETURN_CODE=254
fi

if [[ ${RETURN_CODE} -eq 0 ]]; then
    echo "Loaded wekafsio ${LOADED_IO} and wekafsgw ${LOADED_GW} match ${RUNNING_VERSION}."
fi

exit ${RETURN_CODE}
