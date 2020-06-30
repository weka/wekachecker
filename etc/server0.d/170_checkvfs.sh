#!/bin/bash

DESCRIPTION="Checking if VFS creation is supported"

if grep "Amazon Linux" /etc/os-release &> /dev/null; then   
	write_log "Not checking VFs creation because it is N/A on AWS"
	ret="0"
	exit $ret
fi 

# Put your stuff here
which mst &> /dev/null
if [ $? -ne 0 ]; then
	write_log "Mellanox MST configuration tool not found, you might not have OFED drivers installed"
	ret="1"
	exit $ret
fi

which mlxconfig &> /dev/null
if [ $? -ne 0 ]; then
	write_log "Mellanox mlxconfig tool not found, you might not have OFED drivers installed"
	ret="1"
	exit $ret
fi

mst_status=`sudo mst status | grep "MST PCI configuration module is not loaded"`
if [ ! -z "$mst_status" ]; then
	write_log "Mellanox configuration module is not loaded, starting"
	sudo mst start &> /dev/null
	if [ $? -ne 0 ]; then
		write_log "Could not start Mellanox configuration module properly"
		ret="1"
		exit $ret
	else
		write_log "Mellanox configuration module started successfully"
		device_name=`sudo mst status | grep "\/dev" | awk {'print $1'}`
		if [ -z "$device_name" ]; then
			write_log "Device name is not found"
			ret="1"
			exit $ret
		else
			rm -rf /tmp/device_list.txt
			sudo mst status | grep "\/dev" | awk {'print $1'} >> /tmp/device_list.txt
			num_of_devices=`cat /tmp/device_list.txt | wc -l`
			for i in `seq $num_of_devices`; do
				device_name=`cat /tmp/device_list.txt | head -$i | tail -1`
				write_log "Device name found: $device_name, checking if SRIOV_EN is set to 1 and VFS functions available"
				sriov_status=`mlxconfig -d "$device_name" q | grep -i "SRIOV_EN" | awk '{print $2}' | sed 's/ //g'`
				if [ -z "$sriov_status" ]; then
					write_log "Could not get SRIOV status properly, something went wrong in mlxconfig -d $device_name q command output"
					ret="1"
				else
					write_log "SRIOV_EN is set to: $sriov_status"
					ret="0"
				fi
				vfs_status=`mlxconfig -d $device_name q | grep -i "NUM_OF_VFS" | awk '{print $2}' | sed 's/ //g'`
				if [ -z "$vfs_status" ]; then
					write_log "Could not determine number of VFS number, something went wrong with mlxconfig -d $device_name q command output"
					ret="1"
				else
					if [ "$vfs_status" -le "1" ]; then
						write_log "VFS number: $vfs_status is not going to work properly with the system"
						write_log "Please run the following command the set the number of VFS to 16: mst start && mlxconfig -y -d $device_name set SRIOV_EN=1 NUM_OF_VFS=16"
						ret="1"
					else
						write_log "Number of available VFS on device $device_name is $vfs_status"
						ret="0"
					fi
				fi
			done
		fi
	fi
else
	write_log "Output of mst status was improper or MST configuration module is loaded, please stop with mst stop"
	ret="1"
fi
sudo mst stop 1 >/dev/null 2>&1


exit $ret
