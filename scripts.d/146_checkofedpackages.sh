#!/bin/bash

DESCRIPTION="Check for OFED Required Packages..."
SCRIPT_TYPE="parallel"

# Checking if OS has the required packages installed for proper Weka.IO runtime
install_needed=""
remove_needed=""

missing_list=()

if [[ $ID_LIKE == *rhel* ]]; then
	echo "REQUIRED packages missing for OFED installation (Red Hat based system)"

	red_hat_pkg_list_ofed=( "pciutils" "cairo" "gcc-gfortran" 
                            "tcsh" "lsof" "tcl" "tk" )

	if [ ! -d /etc/amazon ]; then	# Amazon does not use OFED
		for i in ${red_hat_pkg_list_ofed[@]}; do
			rpm -q $i &> /dev/null
			if [ $? -eq 1 ]; then
                missing_list+=($i)
				ret="1" # FAIL
                install_needed="$install_needed $i"
			fi
		done
	fi

    needed_actions="${install_needed}"
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

elif [[ $ID_LIKE == *debian* ]]; then
	echo "REQUIRED packages missing for OFED installation (Debian/Ubuntu based system)"
	debian_pkg_list_ofed=( "pciutils" "cairo" "python-libxml2" \
                            "tcsh" "lsof" "tcl" "tk" "zlib1g-dev" "curl" )

	for d in ${debian_pkg_list_ofed[@]}; do
		dpkg -l | awk {'print $2'} | grep -i $d &> /dev/null
		if [ $? -eq 1 ]; then
            missing_list+=($d)
			ret="1" # FAIL
            install_needed="$install_needed $i"
		fi
	done

  needed_actions="${install_needed}"
  if [[ "$FIX" == "True" && "${needed_actions}" != "" ]]; then
      echo "--fix specified, attempting to install/remove packages"
      if [ "${install_needed}" != "" ]; then
          sudo apt-get update
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
