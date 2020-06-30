#!/bin/bash

DESCRIPTION="Check /opt/weka for sufficient capacity..."

# Checking if installation folder has enough free space for Weka.IO install - general requirement is 26Gb and additional 10Gb per CPU core

df -h | grep opt &> /dev/null
if [ $? -eq 1 ]; then
        # No locally mounted /opt/dir to seperate partition, which means opt is on /
        local_free_space=`df -h / | tail -1 | awk {'print $4'} | sed 's/[a-zA-Z]//g' | sed 's/\.[0-9]//g'`
else
        # There is locally mounted /opt/dir to seperate partition, which means weka should be in /opt
        local_free_space=`df -h | grep opt | head -1 | awk {'print $4'} | sed 's/[a-zA-Z]//g' | sed 's/\.[0-9]//g'`
fi
num_of_cpus=`lscpu|grep "CPU(s):"|head -1 |awk {'print $2'}`
num_of_sockets=`lscpu | grep -i "Socket" | tail -1 | awk {'print $2'}`
num_of_threads=`lscpu | grep -i "Thread(s) per core" | cut -d: -f2 `
num_of_cores=`echo $(($num_of_cpus/$num_of_threads/$num_of_sockets))`
set +x
if [ "$num_of_cores" -le "19" ]; then
	space_needed=`echo $((($num_of_cores*10)+26))`
	space_missing=`echo $((-1*($local_free_space-$space_needed)))`
else
	space_needed=`echo $(((19*10)+26))`
	space_missing=`echo $((-1*($local_free_space-$space_needed)))`
fi

if [ "$space_needed" -le "$local_free_space" ]; then
	write_log "There is enough space to run Weka.IO on this node"
	ret="0"
else
	write_log "There are a total $num_of_cores cores, this requires "$space_needed"G for proper Weka.IO runtime, there is only "$local_free_space"G available, please free: "$space_missing"G in /opt"
	ret="254"
fi

exit $ret
