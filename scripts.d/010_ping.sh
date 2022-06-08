#!/bin/bash

DESCRIPTION="IP Ping/Jumbo Frames test"
# script type is single, parallel, or sequential
SCRIPT_TYPE="single"

# Put your stuff here
ret="1"

which ping &> /dev/null
if [ $? -eq 1 ]; then
	if [ "$DIST" == "ubuntu" ]; then
		PACKAGE="iputils-ping"
	else
		PACKAGE="iputils"
	fi
	echo "ping not found." 
	if [ "$FIX" == "True" ]; then
		echo "Fix requested. Installing ping"
		if [ "$DIST" == "ubuntu" ]; then
			sudo apt-get install iputils-ping
		else
			sudo yum -y install iputils
		fi
	else
		echo "Please install $PACKAGE or use --fix option"
		exit "255" 
	fi
fi

let ERRORS=0
let WARN=0
IFLAST="none"
IFHW="none"
#
# check ssh connectivity, if given hostnames/ips on command line
#
if [ $# -gt 0 ]; then
	echo Running from `hostname`
	for i in $*
	do
	  # resolve the name, in case we have a name, not an ip addr
      IPRESOLVED=`ping -c1 $i | head -1 | cut '-d ' -f3`
      DESTIPADDR=${IPRESOLVED:1:-1}
	  # using sed below because the output of the 'ip' command isn't strictly columnar; data may be in different columns
	  # determine which interface will be used to get to this address
	  IFS=' ';RT=(`ip -o route get $DESTIPADDR`)
	  IF=`echo ${RT[*]} | grep -oP "dev \K\S*"`
	  if [ $IF != $IFLAST ]; then IFLAST=$IF; IFHW="none"; fi
	  DEVINFO=`ip -o link show dev $IF`
	  LINKTYPE=`echo $DEVINFO | grep -oE "(ether|infiniband|loopback)"` # link type
	  CONF_MTU=`echo $DEVINFO | grep -oP "mtu \K[0-9]*"` # extract mtu 

	  # LINK should now be either "ether" or "infiniband" or "loopback"
	  if [ "$LINKTYPE" == "loopback" ]; then
	    continue  # skip the loopback interface (no sense in pinging myself)
	  fi
	  if [ ${RT[1]} == "via" ]; then
	  	echo "    Destination $DESTIPADDR is routed via gw ${RT[2]} on dev $IF"
	    if [ $IFHW == "none" ]; then IFHW=`lshw -class network -short | grep $IF`; fi
		echo "          Interface HW: $IFHW"
		echo "          Is routed destination intentional?"
		let WARN=$WARN+1
	  fi
      if [ "$LINKTYPE" == "ether" ]; then
	    MTU="9000"
	    PINGMTU="8972"
      elif [ "$LINKTYPE" == "infiniband" ]; then
	    MTU="4092"
	    PINGMTU="4064"
      else
        echo "Error determining target MTU for $LINKTYPE - $DEVINFO"
	    if [ $IFHW == "none" ]; then IFHW=`lshw -class network -short | grep $IF`; fi
		echo "          Interface HW: $IFHW"
	    let WARN=$WARN+1
      fi

      if [ "$CONF_MTU" != "$MTU" ]; then
        	echo "    FAIL: `hostname` interface $IF MTU is $CONF_MTU not $MTU (for ping to $DESTIPADDR)"
	    	if [ $IFHW == "none" ]; then IFHW=`lshw -class network -short 2> /dev/null | grep $IF`; fi
			echo "          Interface HW: $IFHW"
			echo "          Is $IF a dataplane interface?"
        	exit "1"
      fi
	  # check for jumbo frames working correctly as well as basic connectivity.
	  sudo ping -M 'do' -c 2 -i 0.2 -s $PINGMTU  $i &> /dev/null
	  if [ ! $? -eq 0 ]; then	# change to not eq 0
		echo $PINGOUT
		echo "    Host $i JUMBO FRAME ping error over $IF."
		echo "          Interface HW: $IFHW"
		echo "          MTU set properly on $IF - check for incorrect MTU on all ports on path to $DESTIPADDR"
		let WARN=$WARN+1
	  else
		echo "        OK: Host $i JUMBO ping test passed over $IF."
	  fi
	done
else
	echo "No hosts specified, skipping ping/jumbo frame connectivity test."
fi

#echo "There were $ERRORS failures"

#if [ $ERRORS -gt 0 ]; then
#	exit 255		# if we can't ping all the servers, we can't continue
#elif [ $WARN -gt 0 ]; then
if [ $WARN -gt 0 ]; then
	exit "254"		# jumbo frames not enabled/working on all, so warn
fi
exit "0"
