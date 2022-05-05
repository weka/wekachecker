#!/bin/bash

DESCRIPTION="Check for IOMMU disabled"
SCRIPT_TYPE="parallel"


find /sys | grep dmar &> /dev/null
if [ $? == 0 ]; then
    write_log "ERROR: IOMMU is enabled on `hostname`"
    exit 1
fi

exit 0
