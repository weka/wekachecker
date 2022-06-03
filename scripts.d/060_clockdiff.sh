#!/bin/bash

DESCRIPTION="Verify timesync"
# script type is single, parallel, or sequential
SCRIPT_TYPE="single"

ret="0"

# Put your stuff here
which clockdiff &> /dev/null
if [ $? -eq 1 ]; then
	if [ "$DIST" == "ubuntu" ]; then
		PACKAGE="iputils-clockdiff"
	else
		PACKAGE="iputils"
	fi
	echo "clockdiff not found." 
	if [ "$FIX" == "True" ]; then
		echo "Fix requested. Installing clockdiff"
		if [ "$DIST" == "ubuntu" ]; then
			sudo apt-get install iputils-clockdiff
		else
			sudo yum -y install iputils
		fi
		which clockdiff &> /dev/null
		if [ $? -eq 1 ]; then
			echo "Fix failed - clockdiff still not found"
			echo "Please install $PACKAGE"
			exit "254"
		fi
	else
		echo "Please install $PACKAGE or use --fix option"
		exit "254" #  WARN
	fi
fi

echo
for i in $*
do
    RESULT=`clockdiff $i`
	DIFF=`echo $RESULT | awk '{ print $2 + $3 }'`
	if [ $DIFF -lt 0 ]; then let DIFF="(( 0 - $DIFF ))"; fi
	if [ $DIFF -gt 10 ]; then # up to 10ms is allowed
		echo "    Host $i is not in timesync: time diff is $DIFF ms"
		ret="1"
	else
		echo "        Host $i timesync ok; diff is $DIFF"
	fi
done


exit $ret
