#!/bin/bash

DESCRIPTION="Check for IOMMU disabled"
SCRIPT_TYPE="parallel"


find /sys | grep dmar &> /dev/null
if [ $? == 0 ]; then    # found a dmar, which we don't want
    write_log "ERROR: IOMMU is enabled on `hostname`"
    exit "1"
else
    write_log "IOMMU disabled"
fi

exit "0"
