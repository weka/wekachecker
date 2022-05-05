#!/bin/bash

DESCRIPTION="IP Jumbo Frames test"
# script type is single, parallel, or sequential
SCRIPT_TYPE="single"


# Put your stuff here

let ERRORS=0
let WARN=0
#
# check ssh connectivity, if given hostnames/ips on command line
#
if [ $# -gt 0 ]; then
	for i in $*
	do
	  # resolve the name, in case we have a name, not an ip addr
    TMP=`ping -c1 $i | head -1 | cut '-d ' -f3`
    TMP2=${TMP:1}
    IPADDR=${TMP2%")"}
	  # using sed below because the output of the 'ip' command isn't strictly columnar; data may be in different columns
	  # determine which interface will be used to get to this address
	  IF=`ip -o route get $IPADDR | sed 's/.*dev //;s/ .*//'`

	  # determine if ETH or IB
	  LINK=`ip -o -f link address show dev $IF | sed 's/.*link\///;s/ .*//'`  # extract link/ether
	  CONF_MTU=`ip -o -f link address show dev $IF | sed 's/.*mtu //;s/ .*//'` # extract mtu 9000

	  # LINK should now be either "ether" or "infiniband" or "loopback"
	  if [ "$LINK" == "loopback" ]; then
	    continue  # skip the loopback interface (no sense in pinging myself)
    elif [ "$LINK" == "ether" ]; then
	    MTU="9000"
	    PINGMTU="8972"
    elif [ "$LINK" == "infiniband" ]; then
	    MTU="4092"
	    PINGMTU="4064"
    else
      echo "Error determining target MTU"
    fi

    if [ "$CONF_MTU" != "$MTU" ]; then
      echo "Jumbo frames not configured on interface $IF on `hostname`"
      exit 254
    fi

		# check for jumbo frames working correctly as well as basic connectivity.
		sudo ping -M do -c 2 -i 0.2 -s $PINGMTU  $i &> /dev/null
		if [ $? -eq 1 ]; then	# 1 == error exists
			echo $PINGOUT
			echo "WARNING: Host $i JUMBO FRAME ping error."
			let WARN=$WARN+1
			# jumbo frame ping failed, let's see if we can ping with normal mtu
			#sudo ping -c 10 -i 0.2 -q $i &> /dev/null
			#if [ $? -eq 1 ]; then
			#	echo "ERROR: Host $i general ping error."
			#	let ERRORS=$ERRORS+1
			#else
			#	echo "Host $i non-jumbo ping test passed."
			#fi
		else
			echo "Host $i JUMBO ping test passed."
		fi
	done
else
	echo "No hosts specified, skipping ssh connectivity test."
fi

#echo "There were $ERRORS failures"

#if [ $ERRORS -gt 0 ]; then
#	exit 255		# if we can't ping all the servers, we can't continue
#elif [ $WARN -gt 0 ]; then
if [ $WARN -gt 0 ]; then
	exit 254		# jumbo frames not enabled/working on all, so warn
fi
exit 0
