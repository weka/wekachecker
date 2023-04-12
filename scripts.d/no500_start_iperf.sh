#!/bin/bash

DESCRIPTION="Start an iperf server"
SCRIPT_TYPE="parallel"

which iperf &> /dev/null
if [ $? == 1 ]; then
    echo "ERROR: iperf not installed"
    exit "255"
fi

# Put your stuff here
sudo pkill iperf	# make sure it's not already running
#(iperf -s &> /dev/null) &
(iperf -s ) &
echo "iperf server started"
sleep 1
exit 0
