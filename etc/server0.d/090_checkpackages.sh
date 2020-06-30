#!/bin/bash

DESCRIPTION="Check for required Packages..."

# Checking if OS has the required packages installed for proper Weka.IO runtime
#which dpkg &> /dev/null
#if [ $? -eq 1 ]; then
if [ "$DIST" == "redhat" ]; then
	write_log "Running on top of Red Hat based system"
	red_hat_pkg_list_weka=( "elfutils-libelf-devel" "glibc" "glibc-headers" "glibc-devel" \
		"gcc" "make" "perl" "rpcbind" )
	red_hat_pkg_list_ofed=( "pciutils" "gtk2" "atk" "cairo" "gcc-gfortran" "tcsh" "lsof" "tcl" "tk" )
	red_hat_pkg_list_general=( )
	#red_hat_pkg_list_no=( "network-manager" )
	red_hat_pkg_list_no=( )
	for i in ${red_hat_pkg_list_weka[@]}; do
		rpm -q $i &> /dev/null
		if [ $? -eq 1 ]; then
			write_log "Package $i is REQUIRED for proper weka installation"
			ret="1"
		fi
	done
	if [ ! -d /etc/amazon ]; then	# Amazon does not use OFED
		for i in ${red_hat_pkg_list_ofed[@]}; do
			rpm -q $i &> /dev/null
			if [ $? -eq 1 ]; then
				write_log "Package $i is REQUIRED for proper OFED installation"
				ret="1"
			fi
		done
	fi
	for i in ${red_hat_pkg_list_general[@]}; do
		rpm -q $i &> /dev/null
		if [ $? -eq 1 ]; then
			write_log "Package $i is missing for RECOMMENDED installation for Weka runtime"
			ret="1"
		fi
	done
	for i in ${red_hat_pkg_list_no[@]}; do
		rpm -q $i &> /dev/null
		if [ $? -eq 1 ]; then
			write_log "Package $i is installed but NOT RECOMMENDED for Weka runtime"
			ret="1"
		fi
	done
else
	write_log "Running on top of Debian based system (Ubuntu)"
	debian_pkg_list_weka=( "elfutils" "libelf-dev" "linux-libc-dev" "glibc-source" "make" "perl" "rpcbind" \
		"elfutils" )
	debian_pkg_list_ofed=( "pciutils" "gtk2" "atk" "cairo" "python-libxml2" "tcsh" "lsof" "tcl" "tk" )
	debian_pkg_list_general=( "net-tools" "wget" "sg3-utils" "gdisk" "ntpdate" )
	#debian_pkg_list_no=( "network-manager" )
	debian_pkg_list_no=( )
	for i in ${debian_pkg_list_weka[@]}; do
		dpkg -l | awk {'print $2'} | grep -i $i &> /dev/null
		if [ $? -eq 1 ]; then
			write_log "Package $i is missing for proper weka installation"
			ret="1"
		fi
	done
	for d in ${debian_pkg_list_ofed[@]}; do
		dpkg -l | awk {'print $2'} | grep -i $d &> /dev/null
		if [ $? -eq 1 ]; then
			write_log "Package $d is REQUIRED for proper OFED installation"
			ret="1"
		fi
	done
	for e in ${debian_pkg_list_general[@]}; do
		dpkg -l | awk {'print $2'} | grep -i $e &> /dev/null
		if [ $? -eq 1 ]; then
			write_log "Package $e is REQUIRED for RECOMMENDED installation for Weka runtime"
			ret="1"
		fi
	done
	for z in ${debian_pkg_list_no[@]}; do
		dpkg -l | awk {'print $2'} | grep -i $z &> /dev/null
		if [ $? -eq 1 ]; then
			write_log "Package $z is installed but NOT RECOMMENDED for Weka runtime"
			ret="1"
		fi
	done
fi
exit $ret
