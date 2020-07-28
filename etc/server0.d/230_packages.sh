#!/bin/bash

DESCRIPTION="Make sure required packages are installed on all nodes"

PACKAGES="elfutils-libelf-devel \
glibc \
glibc-headers \
glibc-devel \
gcc \
make \
perl \
rpcbind \
pciutils \
gtk2 \
atk \
cairo \
gcc-gfortran \
tcsh \
lsof \
tcl \
tk \
sysstat \
strace \
ipmitool \
tcpdump \
telnet \
nmap \
net-tools \
dstat \
numactl \
numactl-devel \
python \
python3 \
automake \
libaio \
libaio-devel \
perl \
lshw \
hwloc \
pciutils \
lsof \
wget \
bind-utils \
vim-enhanced \
nvme-cli \
nfs-utils \
initscripts \
screen \
tmux \
git \
sshpass \
python-pip \
python3-pip \
lldpd \
bmon \
nload \
pssh \
pdsh \
iperf \
fio \
htop"

# make sure epel-release and pdsh/pssh are installed here first...
if [ ! -d /etc/amazon ]; then
	echo "Installing epel-release on this node"
	yum -y install epel-release &> /tmp/epel-install.log
	if [ $? -ne 0 ]; then
		echo "Unable to install epel-release.  See /tmp/epel-install.log for details."
		exit 254
	fi
fi
echo "Installing pdsh & pssh on this node"
yum -y install pdsh pssh &> /tmp/package-install.log
if [ $? -ne 0 ]; then
	echo "Unable to install pdsh & pssh.  See /tmp/package-install.log for details."
	exit 254
fi

# pdsh needs a comma-separated list of hosts
#pdsh_hosts=`echo $* | sed 's/ /,/g'`

echo "Installing packages"
yum -y install $PACKAGES &> /tmp/packages-install.log
if [ $? -ne 0 ]; then
	echo "Failed install of packages - check /tmp/packages-install.log on all the nodes"
	exit 1
fi
exit 0
