#!/bin/bash

DESCRIPTION="Check for IOMMU disabled"
SCRIPT_TYPE="parallel"



#find /sys | grep dmar &> /dev/null
#if [ $? == 0 ]; then    # found a dmar, which we don't want
#    write_log "ERROR: IOMMU is enabled on `hostname`"
#    exit "1"
#else
#    write_log "IOMMU disabled"
#fi

iommuclass=`ls /sys/class/iommu | wc -l`
iommugroups=`ls /sys/kernel/iommu_groups | wc -l`
if [ $iommuclass -eq "0" ] && [ $iommugroups -eq "0" ]; then    # check for iommu devices
    write_log "IOMMU not configured on `hostname`"
    ret="0"
else
    write_log "IOMMU configured on `hostname` - should be disabled"
    ret="1"
fi

exit $ret


