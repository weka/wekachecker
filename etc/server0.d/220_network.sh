#!/bin/bash

DESCRIPTION="Check Network interfaces"

# some of this is easier to do in bash...

# get our ip interfaces
IP_INTERFACES=""
RAW_IP_INTERFACES=`ip addr | grep "inet " | grep -v 127.0.0.1 | while read myline; do echo $myline | tr ' ' '\n' | tail -1; done`
for i in $RAW_IP_INTERFACES; do
        IP_INTERFACES="$IP_INTERFACES `ip addr show dev $i | head -1 | grep -v bond | awk -F: '{print $2}'`"
done

WEKA_INTERFACES=""

for IFACE in $IP_INTERFACES; do
	ETH_DRIVER=`ethtool -i $IFACE | awk '/^driver/ {print $2}'`
	#
	# Check jumbo frames while we're at it
	#
	#IF_MTU=`cat /sys/class/net/$IFACE/mtu`

	# skip this one, it's not jumbo frames?
	#if [ $IF_MTU -lt 4092 ]; then
	#	continue	
	#fi

	case $ETH_DRIVER in
		ena)
			WEKA_INTERFACES="$WEKA_INTERFACES $IFACE"
			;;
		mlx5_core)
			WEKA_INTERFACES="$WEKA_INTERFACES $IFACE"
			;;
		"mlx5_core[ib_ipoib]")
			WEKA_INTERFACES="$WEKA_INTERFACES $IFACE"
			;;
		mlx4_core)
			WEKA_INTERFACES="$WEKA_INTERFACES $IFACE"
			;;
		ixgbevf)
			WEKA_INTERFACES="$WEKA_INTERFACES $IFACE"
			;;
		intel)
			WEKA_INTERFACES="$WEKA_INTERFACES $IFACE"
			;;
		*)
			;;
	esac
done

# WEKA_INTERFACES is now a list of interface names we're interested in
WEKA_IPS=""
for i in $WEKA_INTERFACES; do
	WEKA_IPS="$WEKA_IPS `ip a s $i | grep "inet " | awk '{print $2}'`"
done

echo "checking interfaces \"" $WEKA_INTERFACES "\""
# now, get it into JSON format

# some things are easier in python

#!/usr/bin/env python
NET=`python3 -c '

import subprocess
import json
import argparse

# returns the ipaddr/mask for the specified interface 
def fetch_ip( interface ):
    cmd = ["sudo", "ip", "addr", "show", "dev", interface]

    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    ret = p.wait()
    for line in p.stdout:
        linelist = line.split()
        if linelist[0] == "inet":
            return linelist[1]

    return None

# returns the ipaddr/mask for the specified interface 
def fetch_driver( interface ):
    cmd = ["ethtool", "-i", interface]

    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    ret = p.wait()
    for line in p.stdout:
        linelist = line.split()
        if linelist[0] == "driver:":
            return linelist[1]

    return None

# Parse arguments
parser = argparse.ArgumentParser(description="get ip information")
parser.add_argument("interfaces", metavar="interfaces", type=str, nargs="+",
                    help="interfaces to look at")
args = parser.parse_args()

network={}
for iface in args.interfaces:
    ipinfo = fetch_ip( iface )
    temp = ipinfo.split( "/" )
    ip = temp[0]
    maskbits = temp[1]
    driver = fetch_driver( iface )

    network[iface] = { "ip":ip, "maskbits":maskbits, "driver":driver }

    print( network )
    #print( json.dumps(network, indent=2, sort_keys=True) )

' $WEKA_INTERFACES`
echo $NET
if [ ${#NET} -lt 10 ]; then ret=1; else ret=0; fi
exit $ret
