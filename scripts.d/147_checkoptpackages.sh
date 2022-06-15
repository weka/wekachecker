#!/bin/bash

DESCRIPTION="Check for Recommended Packages..."
SCRIPT_TYPE="parallel"

# Checking if OS has the required packages installed for proper Weka.IO runtime
install_needed=""
remove_needed=""

missing_list=()

if [ "$DIST" == "redhat" ]; then
	write_log "RECOMMENDED packages missing for WEKA runtime (RedHat based system):"

	red_hat_pkg_list_general=( "epel-release" "sysstat" "strace" "ipmitool" "tcpdump" "telnet" "nmap" "net-tools" \
        "dstat" "numactl" "numactl-devel" "python" "python3" "libaio" "libaio-devel" "perl" \
        "lshw" "hwloc" "pciutils" "lsof" "wget" "bind-utils" "nvme-cli" "nfs-utils" \
        "screen" "tmux" "git" "sshpass" "python-pip" "python3-pip" "lldpd" "bmon" \
        "nload" "pssh" "pdsh" "iperf" "fio" "htop" )

	for i in ${red_hat_pkg_list_general[@]}; do
		rpm -q $i &> /dev/null
		if [ $? -eq 1 ]; then
            missing_list+=($i)
			ret="254"   # WARNING
            install_needed="$install_needed $i"
		fi
	done

    needed_actions="${install_needed} ${remove_needed}"
    if [[ "$FIX" == "True" && "${needed_actions}" != "" ]]; then
        echo "--fix specified, attempting to install/remove packages"
        if [ "${install_needed}" != "" ]; then
            sudo yum -y install ${install_needed}
            if [ $? -ne 0 ]; then
                echo "Failure while installing packages."
                ret="1" # FAIL
            fi
        fi
    fi

else
	write_log "RECOMMENDED packages missing for WEKA runtime (Debian/Ubuntu based system):"

	debian_pkg_list_general=( "net-tools" "wget" "sg3-utils" "gdisk" "ntpdate" "ipmitool" "sysstat" "strace" \
        "tcpdump" "telnet" "nmap" "hwloc" "numactl" "python3" "pciutils" "lsof" "wget" "bind9-utils" \
        "nvme-cli" "nfs-utils" "screen" "tmux" "git" "sshpass" "python-pip" "python3-pip" "lldpd" "bmon" "nload" \
        "pssh" "pdsh" "iperf" "fio" "htop" )

	for e in ${debian_pkg_list_general[@]}; do
		dpkg -l | awk {'print $2'} | grep -i $e &> /dev/null
		if [ $? -eq 1 ]; then
			missing_list+=($e)
			ret="254"   # WARNING
            install_needed="$install_needed $i"
		fi
	done

    needed_actions="${install_needed}"
    if [[ "$FIX" == "True" && "${needed_actions}" != "" ]]; then
        echo "--fix specified, attempting to install/remove packages"
        if [ "${install_needed}" != "" ]; then
            sudo apt-get -y install ${install_needed}
            if [ $? -ne 0 ]; then
                echo "Failure while installing packages."
                ret="1" # FAIL
            fi
        fi
    fi
fi

out=" : : : "
for (( i=0; i<"${#missing_list[@]}"; i++ )); do
    out+="${missing_list[$i]}: : "
    n=i+1
    mod=$((n%5))
    if [[ $mod == "0" ]]; then
        out+="\n : : : "
    fi
done
printf "$out\n" | column -t -s ":"
printf "\n"

exit $ret
