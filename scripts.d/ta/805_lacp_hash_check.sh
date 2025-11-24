#!/bin/bash

set -ue # Fail with an error code if there's any sub-command/variable error

DESCRIPTION="Hashing on DPDK LACP links is only supported on select NICs"
SCRIPT_TYPE="single"
JIRA_REFERENCE="WEKAPP-539450"
WTA_REFERENCE=""
RETURN_CODE=0


# WEKAPP-539450
# https://www.notion.so/wekaio/LACP-CX6-DX-and-newer-2a030b0d101c8048a9bbc587e0242f87#2a330b0d101c80cbbbe9e689f0e7982f
# CX-6 and older adapters
#  -Use the Verbs path
#  -Support only queue-affinity mode (file lag_port_select_mode cannot be changed)

# CX-6 LX
#  -Uses Verbs path
#  -Default lag_port_select_mode is hash
#  -Changing to queue_affinity reverts to round-robin queue affinity

# CX-6 DX and newer
#  -Require DevX-level control (not available via Verbs API)
#  -Legacy mode hardware LAG is broken, the bond is treated as a single port
#  -On the Weka side, enabling DevX-level control by enabling HAVE_MLX5DV_DR_ACTION_DEST_DEVX_TIR , restored LACP and hash-based distribution on CX6-DX and newer (not effecting the behavior of older nics).
#  -Changing lag_port_select_mode to queue_affinity again breaks LACP for those nics, and the bond is treated as a single port.

# lag_port_select_mode
#  echo "hash" > /sys/class/net/<Interface Name>/compat/devlink/lag_port_select_mode
#  This feature requires to set LAG_RESOURCE_ALLOCATION to 1 with mlxconfig
#  dmesg *may* indicate 'devlink op lag_port_select_mode doesn't support hw lag' on unsupported models.

# Process
# - Iterate over backend management processes (weka cluster process -b -F role=MANAGEMENT -F status=UP)
  
# - Invoke manhole, based on process id from above (weka debug manhole --node=<Process Id> network_get_dpdk_ports)
  
# - Check if bondType is BOND, if so:
#   - Validate bondMode (ACTIVE_BACKUP not supported)
#   - Conditionally check hashPolicy, based on ip and netmaskBits
#   - Use container id to obtain NIC model (weka cluster container net 0 -J | egrep -w -e device -e name)

while read PID CID CONTAINER HOSTNAME; do
    while read LINE; do
        if [[ $LINE =~ "bondMode:"(.*)"bondType:"(.*)"hashPolicy:"(.*)"netdevName:"(.*) ]]; then
            BOND_MODE="${BASH_REMATCH[1]}"
            BOND_TYPE="${BASH_REMATCH[2]}"
            HASH_MODE="${BASH_REMATCH[3]}"
            NIC="${BASH_REMATCH[4]}"
            if [[ ${BOND_TYPE} == "BOND" ]]; then
			
                # Only LACP is supported
                if [[ ${BOND_MODE} != "IEEE_802_3AD" ]]; then
                    echo "WARN: ${HOSTNAME} (${CONTAINER}) bonding mode is using unsupported mode ${BOND_MODE}"
                    RETURN_CODE=254
                fi
			
                # Check xmit hash policy
                if [[ ${HASH_MODE} == "LAYER2" ]]; then
                    echo "WARN: ${HOSTNAME} xmit hash policy for NIC ${NIC} set to layer2."
                    RETURN_CODE=254
                fi
			
                # Check to see if the NIC supports hardware hashing or not
                while read LINE; do
                    if [[ $LINE =~ "name:${NIC}device:"(.*) ]]; then
                        NIC_MODEL="${BASH_REMATCH[1]}"
                        # MT Number mapping
                        #  MT28508 - ConnectX-6 Lx dual port
                        #  MT28908 - ConnectX-6 Dx dual port
                        #  MT41208 - ConnectX-7 dual port
                        #  MT41608 - ConnectX-7 dual port
                        if [[ ! "${NIC_MODEL}" =~ MT28508 && \
                              ! "${NIC_MODEL}" =~ MT28908 && \
                              ! "${NIC_MODEL}" =~ MT41208 && \
                              ! "${NIC_MODEL}" =~ MT41608 ]]; then
                            echo "WARN: ${HOSTNAME} (${CONTAINER}) NIC ${NIC} may not support hashing on bonded links."
                            RETURN_CODE=254
                        fi
                    fi
                done < <( weka cluster container net ${CID} -J | egrep -w -e device -e name | paste - - | tr -d \"\,[:blank:])
				
            fi
        fi
    done < <(weka debug manhole --node=${PID} network_get_dpdk_ports | grep -w -e bondType -e bondMode -e hashPolicy -e netdevName | paste - - - - | tr -d \"\,[:blank:])
done < <(weka cluster process -b -F role=MANAGEMENT -F status=UP -o id,containerId,container,hostname --no-header)


if [[ ${RETURN_CODE} -eq 0 ]]; then
    echo "Bonding properly configured."
else
    echo "Recommended Resolution: Determine NIC compatibility with the bonding mode selected:"
    echo "https://docs.weka.io/planning-and-installation/prerequisites-and-compatibility#networking-ethernet"
fi

exit ${RETURN_CODE}
