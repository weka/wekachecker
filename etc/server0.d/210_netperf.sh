#!/bin/bash


DESCRIPTION="Start an iperf server"

# Put your stuff here
sudo pkill iperf	# make sure it's not already running
#(iperf -s &> /dev/null) &
(iperf -s ) &
write_log "iperf server started"
sleep 1

exit 0
