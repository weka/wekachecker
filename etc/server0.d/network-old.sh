#!/bin/bash

# Return codes are as follows: 0 = Success, >0 = Failure, 255 = Fatal failure (stop all tests)

DESCRIPTION="Check network interfaces"

# Put your stuff here
#write_log "Script name: $0"

#
# Networking
#
# let's look at network interfaces
IP_INTERFACES=""
RAW_IP_INTERFACES=`ip addr | grep "inet " | grep -v 127.0.0.1 | while read myline; do echo $myline | tr ' ' '\n' | tail -1; done`
for i in $RAW_IP_INTERFACES; do
	IP_INTERFACES="$IP_INTERFACES `ip addr show dev $i | head -1 | grep -v bond | awk -F: '{print $2}'`"
done

NUM_IP=`echo $IP_INTERFACES | wc -w`

IS_IB="false"
IS_MLX="false"
NUM_GOOD_IF=0

#
# being tricky/obfuscated :)
goodif()
{
if [ $IF_MTU -ge $1 ]; then
	MTU=$pass
	return 1
else
	MTU=$warn
	let ERRORS=$ERRORS+1
	return 0
fi
}

for IFACE in $IP_INTERFACES; do
	ETH_DRIVER=`ethtool -i $IFACE | awk '/^driver/ {print $2}'`
	#
	# Check jumbo frames while we're at it
	#
	IF_MTU=`cat /sys/class/net/$IFACE/mtu`
	if [ $IF_MTU -ge 4092 ]; then
		MTU=$pass
	else
		MTU=$warn
	fi
	echo -n "IP Interface $IFACE uses driver $ETH_DRIVER "
	case $ETH_DRIVER in
		ena)
			echo -n "${green}AWS ENA interface${reset}"
			goodif 4096
			let NUM_GOOD_IF=$NUM_GOOD_IF+$?
			
			;;
		mlx5_core)
			echo -n "${green}Mellanox CX-5${reset}"
			goodif 4096
			let NUM_GOOD_IF=$NUM_GOOD_IF+$?
			IS_MLX="true"
			;;
		"mlx5_core[ib_ipoib]")
			echo -n "${green}Mellanox CX-5 InfiniBand${reset}"
			goodif 4092
			let NUM_GOOD_IF=$NUM_GOOD_IF+$?
			IS_IB="true"
			IS_MLX="true"
			;;
		mlx4_core)
			echo -n "${green}Mellanox CX-4${reset}"   # confirm this
			goodif 4096
			let NUM_GOOD_IF=$NUM_GOOD_IF+$?
			IS_MLX="true"
			;;
		intel)
			echo -n "${green}Intel card of some sort${reset}"  # repair this
			goodif 4096
			let NUM_GOOD_IF=$NUM_GOOD_IF+$?
			;;
		*)
			#echo -n "${red}Unsupported Adapter - do not use${reset}"  # repair this?  Or just keep quiet?
			;;
	esac
	echo " Jumbo Frames Enabled: [$MTU]"
done

# Number of interfaces check
echo "Number of Supported IP Interfaces: $NUM_GOOD_IF"
if [ $NUM_GOOD_IF -eq 0 ]; then
	ret=1
fi	


exit $ret
