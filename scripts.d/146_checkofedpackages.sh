#!/bin/bash

DESCRIPTION="Check for OFED Required Packages..."
SCRIPT_TYPE="parallel"

# Checking if OS has the required packages installed for proper Weka.IO runtime
install_needed=""
remove_needed=""

if [ "$DIST" == "redhat" ]; then
	write_log "Running on Red Hat based system"

	red_hat_pkg_list_ofed=( "pciutils" "gtk2" "atk" "cairo" "gcc-gfortran" 
                            "tcsh" "lsof" "tcl" "tk" )

	if [ ! -d /etc/amazon ]; then	# Amazon does not use OFED
		for i in ${red_hat_pkg_list_ofed[@]}; do
			rpm -q $i &> /dev/null
			if [ $? -eq 1 ]; then
				write_log "    Package $i is REQUIRED for proper OFED installation"
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

else
	write_log "Running on Debian based system (Ubuntu)"
	debian_pkg_list_ofed=( "pciutils" "gtk2" "atk" "cairo" "python-libxml2" \
                            "tcsh" "lsof" "tcl" "tk" )

	for d in ${debian_pkg_list_ofed[@]}; do
		dpkg -l | awk {'print $2'} | grep -i $d &> /dev/null
		if [ $? -eq 1 ]; then
			write_log "    Package $d is REQUIRED for proper OFED installation"
			ret="1" # FAIL
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
exit $ret
