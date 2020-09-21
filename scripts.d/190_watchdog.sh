#!/bin/bash


DESCRIPTION="Checking for watchdog timer"
SCRIPT_TYPE="parallel"

# Checking for watchdog timer
if [ -c /dev/watchdog ]; then 
	write_log "Watchdog device exists"
	ret="0"
else
	write_log "Watchdog device does not exist"
	ret="254"
	if [ "$FIX" == "True" ]; then
                sudo apt-get install watchdog
		ret="254"
	fi
fi	
exit $ret
