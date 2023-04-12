#!/bin/bash


DESCRIPTION="Stop all iperf servers"
SCRIPT_TYPE="parallel"

# Put your stuff here
sudo pkill iperf	# make sure it's not already running
#(iperf -s &> /dev/null) &
echo "iperf servers stopped"

exit 0
