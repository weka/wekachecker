#!/bin/bash

DESCRIPTION="Check if Network Manager is disabled"
SCRIPT_TYPE="parallel"

# Check if Network Manager is disabled or uninstalled
systemctl list-unit-files | grep -i "networkmanager" &> /dev/null
if [ $? -eq 1 ]; then
        echo "Network Manager is not installed"
        ret="0"
else
        systemctl list-unit-files | grep -i "networkmanager" | head -1 | grep -i "disabled" &> /dev/null
        if [ $? -eq 1 ]; then
#                echo "System has Network Manager enabled in systemctl, please stop and disable Network manager by issuing systemctl stop NetworkManager && systemctl disable NetworkManager"
                echo "Network Manager enabled"
                ret="254"
		if [ "$FIX" == "True" ]; then
			sudo systemctl disable NetworkManager
			echo "NetworkManager disabled"
			ret="0"
		fi
        else
                echo "Network Manager installed, but is disabled"
                ret="0"
        fi
fi

exit $ret
