#!/bin/bash

DESCRIPTION="Checking Linux swap status"
SCRIPT_TYPE="parallel"


swap_state=`swapon -s`

if [ -z "$swap_state" ]; then
	write_log "Swap cache is disabled"
	ret="0"
else
	write_log "Swap cache is enabled on this system, general suggestion would be disabling the cache by issuing: swapoff -a"
	write_log "FIX=$FIX"
	ret="254"
	if [ "$FIX" == "True" ]; then
		sudo swapoff -a
		write_log "Swap turned off"
		ret="254"
	fi
fi

exit $ret
