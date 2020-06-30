#!/bin/bash

DESCRIPTION="Check if SR_IOV and VFS is enabled / supported"

# Checking if SR_IOV and VFS is enabled / supported

if grep "Amazon Linux" /etc/os-release &> /dev/null; then   
	write_log "Not checking SR_IOV because it is N/A on AWS"
	ret="0"
else 

	res=`find /sys/dev* -name 'sriov*'|head -1`
	if [ -z $res ]; then
		write_log "SR_IOV not found on this system, it is either disabled in the BIOS or not supported in this system"
		ret="1"
	else
		# Number of cards which has SR_IOV available for
		count_sriov=`find /sys/dev* -name 'sriov_numvfs'|wc -l`
		write_log "Numer of physical ports which can provide VFS functionality is: $count_sriov"
		# Number of VFS configured per each card, if 0, meanining VFS is not configured
		for i in `find /sys/dev* -name 'sriov_numvfs'`; do echo $i | awk -F\/ {'print $5'}; cat $i; done > /tmp/scan_sriov.txt
		ret="0"
	fi
fi

exit $ret
