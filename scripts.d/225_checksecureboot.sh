#!/bin/bash

DESCRIPTION="Check Secure Boot disabled"
SCRIPT_TYPE="parallel"

# BIOS systems
if ! [ -d /sys/firmware/efi/ ]; then
	write_log 'Not UEFI system, Secure Boot disabled/not possible'
	exit 0
fi

if ! which mokutil; then
	write_log 'mokutil not found, unable to determine Secure Boot status'
	exit 254
fi

sb_state=$(mokutil --sb-state)

if [ "$sb_state" = 'SecureBoot disabled' ]; then
	write_log 'Secure Boot disabled'
	exit 0
elif [ "$sb_state" = 'SecureBoot enabled' ]; then
	write_log 'Secure Boot enabled; disable in the BIOS/UEFI interface'
	exit 254
else
	write_log 'Unable to determine Secure Boot status'
	exit 254
fi
