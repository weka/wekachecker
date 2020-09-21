#!/bin/bash

DESCRIPTION="Checking RAM state for errors"
SCRIPT_TYPE="parallel"


# Put your stuff here
sudo find /sys -name ce\*  | while read f; do echo "$f $(cat $f)"; done &> /dev/null
if [ $? -ne 0 ]; then
	write_log "Errors found in currently installed RAM"
	rm -rf /tmp/dmesg_output.txt /tmp/ram_error.txt &> /dev/null
	dmesg > /tmp/dmesg_output.txt
	cat /tmp/dmesg_output.txt | grep -i -A7 "HANDLING MCE MEMORY ERROR" > /tmp/ram_error.txt
	cat /tmp/ram_error.txt
	ret="1"	
else
	ret="0"
fi

exit $ret
