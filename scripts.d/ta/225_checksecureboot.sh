#!/bin/bash

# No -e: this script inspects the exit codes of the commands it runs.
set -uo pipefail

DESCRIPTION="Check Secure Boot disabled"
SCRIPT_TYPE="parallel"

# The EFI global variable namespace; SecureBoot and SetupMode both live here.
EFI_GLOBAL_GUID="8be4df61-93ca-11d2-aa0d-00e098032b8c"
SB_VAR="/sys/firmware/efi/efivars/SecureBoot-${EFI_GLOBAL_GUID}"

# BIOS systems
if [[ ! -d /sys/firmware/efi ]]; then
    echo "Not UEFI system, Secure Boot disabled/not possible"
    exit 0
fi

SB_STATE=""     # enabled | disabled | unsupported
SB_SOURCE=""
ATTEMPTED=()

# 1. The EFI variable itself: this is the authority, and what mokutil reads. efivarfs
#    prefixes every variable with 4 bytes of EFI attributes, so the boolean sits in
#    the fifth byte -- 1 enabled, 0 disabled.
ATTEMPTED+=("the SecureBoot EFI variable")
if [[ -r ${SB_VAR} ]]; then
    SB_BYTE=$(od -An -t u1 -j 4 -N 1 "${SB_VAR}" 2> /dev/null | tr -d '[:space:]')
    case ${SB_BYTE} in
        1) SB_STATE="enabled"  ; SB_SOURCE="the SecureBoot EFI variable" ;;
        0) SB_STATE="disabled" ; SB_SOURCE="the SecureBoot EFI variable" ;;
    esac
elif [[ ! -e ${SB_VAR} ]]; then
    # Absence only means something when efivarfs is mounted and populated: firmware
    # that implements Secure Boot always publishes the variable. If the variable
    # exists but is unreadable (not root), fall through to the other sources instead.
    shopt -s nullglob
    EFI_GLOBAL_VARS=(/sys/firmware/efi/efivars/*-"${EFI_GLOBAL_GUID}")
    shopt -u nullglob
    if [[ ${#EFI_GLOBAL_VARS[@]} -gt 0 ]]; then
        SB_STATE="unsupported"
        SB_SOURCE="the absence of a SecureBoot EFI variable"
    fi
fi

# 2. systemd's bootctl, which reads the same variable and ships with systemd.
if [[ -z ${SB_STATE} ]] && command -v bootctl &> /dev/null; then
    ATTEMPTED+=("bootctl status")
    while read -r LINE; do
        case ${LINE} in
            *"Secure Boot: enabled"*)  SB_STATE="enabled"  ; SB_SOURCE="bootctl" ;;
            *"Secure Boot: disabled"*) SB_STATE="disabled" ; SB_SOURCE="bootctl" ;;
        esac
    done < <(bootctl status 2> /dev/null)
fi

# 3. mokutil, if it happens to be installed.
if [[ -z ${SB_STATE} ]] && command -v mokutil &> /dev/null; then
    ATTEMPTED+=("mokutil --sb-state")
    # It exits non-zero when the firmware has no Secure Boot support, so the output
    # matters and the exit code does not.
    MOKUTIL_OUT=$(mokutil --sb-state 2>&1)
    case ${MOKUTIL_OUT} in
        "SecureBoot enabled"*)        SB_STATE="enabled"     ; SB_SOURCE="mokutil" ;;
        "SecureBoot disabled"*)       SB_STATE="disabled"    ; SB_SOURCE="mokutil" ;;
        *"doesn't support Secure Boot"*|*"not supported"*)
                                      SB_STATE="unsupported" ; SB_SOURCE="mokutil" ;;
    esac
fi

# 4. The kernel's own boot message. Last resort: the ring buffer wraps on long-lived
#    hosts, and kernel.dmesg_restrict can hide it entirely.
if [[ -z ${SB_STATE} ]] && command -v dmesg &> /dev/null; then
    ATTEMPTED+=("dmesg")
    while read -r LINE; do
        case ${LINE,,} in
            *"secure boot enabled"*)  SB_STATE="enabled"  ; SB_SOURCE="dmesg" ;;
            *"secure boot disabled"*) SB_STATE="disabled" ; SB_SOURCE="dmesg" ;;
        esac
    done < <(dmesg 2> /dev/null | grep -ai "secure boot")
fi

case ${SB_STATE} in
    enabled)
        echo "Secure Boot enabled; disable in the BIOS/UEFI interface (per ${SB_SOURCE})"
        echo "Recommended Resolution: Secure Boot refuses unsigned kernel modules, so the"
        echo " wekafs driver will not load while it is on. Disable it in the BIOS/UEFI setup."
        exit 254
        ;;
    disabled)
        echo "Secure Boot disabled (per ${SB_SOURCE})"
        exit 0
        ;;
    unsupported)
        echo "Secure Boot not supported by this system's firmware (per ${SB_SOURCE})"
        exit 0
        ;;
    *)
        echo "Unable to determine Secure Boot status; tried ${ATTEMPTED[*]}"
        echo "Recommended Resolution: run this check as root, or confirm the setting in the"
        echo " BIOS/UEFI setup screen."
        exit 254
        ;;
esac
