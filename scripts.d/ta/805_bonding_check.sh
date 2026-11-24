#!/bin/bash
set -euo pipefail  # fail on error, unset var, and pipeline errors

DESCRIPTION="Bonding sanity check"
SCRIPT_TYPE="parallel"
JIRA_REFERENCE="WEKAPP-539450"
RETURN_CODE=0

# WEKAPP-539450
# https://www.notion.so/wekaio/LACP-CX6-DX-and-newer-2a030b0d101c8048a9bbc587e0242f87#2a330b0d101c80cbbbe9e689f0e7982f
# CX-6 and older adapters (WARNING: not officially supported for bonding)
#  -Use the Verbs path
#  -Support only queue-affinity mode (file lag_port_select_mode cannot be changed)

# CX-6 LX (WARNING: not officially supported for bonding)
#  -Uses Verbs path
#  -Default lag_port_select_mode is hash
#  -Changing to queue_affinity reverts to round-robin queue affinity

# CX-6 DX and newer (CX-7, CX-8; also BlueField-2/3, which integrate CX-6 Dx/CX-7)
#  -Require DevX-level control (not available via Verbs API)
#  -Legacy mode hardware LAG is broken, the bond is treated as a single port
#  -On the WEKA side, enabling DevX-level control by enabling HAVE_MLX5DV_DR_ACTION_DEST_DEVX_TIR, restored LACP and hash-based distribution on CX6-DX and newer (not effecting the behavior of older nics).
#  -Changing lag_port_select_mode to queue_affinity again breaks LACP for those nics, and the bond is treated as a single port.

# LAG port-selection mode (hash vs queue_affinity), per WEKA version:
#  -Before 6.0, WEKA does not pin DPDK TX queues to bond ports; the mlx5 PMD follows the
#   NIC's mode. hash spreads flows over both ports; queue_affinity sends all data from
#   each process on port 1 (control on port 2). Expect hash.
#  -6.0 and later add single-NIC LACP (WEKAPP-554389): WEKA pins TX queues per port and
#   steers RX by ingress port. The docs ask for queue_affinity, but the PMD's TX pinning
#   ignores the mode and the RX steering needs only the NIC's LAG RX port affinity
#   capability. Measured on CX-7 / 6.1.0 in hash mode: per-port TX matched the physical
#   ports exactly. So check that the feature works, not the mode. On failure WEKA falls
#   back to the master port only and raises the DPDKAggrPortFailure alert.
#  -The mode belongs to the NIC's single firmware LAG object, so the kernel and DPDK always
#   share it. compat/devlink/lag_port_select_mode (MOFED) is only the requested mode;
#   the applied one is read from WEKA's DPDK port log or from debugfs.


# Version comparison functions
verlte() { [ "$1" = "$(printf "%s\n%s" "$1" "$2" | sort -V | head -n1)" ]; }
verlt()  { [ "$1" = "$2" ] && return 1 || verlte "$1" "$2"; }

CURRENT_WEKA_VERSION=$(weka version current)
HOSTNAME_SHORT=$(hostname)
VIRTUAL_BOND_FOUND=0
BOND_INTERFACE=""
BOND_MODE=""

# Iterate over compute/frontend/drive/client containers
mapfile -t CONTAINERS < <(weka local ps --output name --no-header | grep -E 'compute|drive|frontend|client' || true)

for CONTAINER in "${CONTAINERS[@]}"; do
    # Get network interfaces for container
    mapfile -t NET_ENTRIES < <(weka local resources -C "$CONTAINER" net --stable -J | grep -w 'name' | tr -d '" ,[:blank:]' || true)
    for NET_ENTRY in "${NET_ENTRIES[@]}"; do
        if [[ "$NET_ENTRY" =~ name:(.*) ]]; then
            NET_NAME="${BASH_REMATCH[1]}"
            if [[ -f "/proc/net/bonding/$NET_NAME" ]]; then
                BOND_INTERFACE="$NET_NAME"
                read -r _ BOND_MODE < "/sys/class/net/${BOND_INTERFACE}/bonding/mode"
            fi
        fi
    done
done

# Prints the DPDK port init logs of this host's WEKA I/O processes, or nothing when the CLI
# has no --logs flag.
dpdk_port_logs() {
    # Captured first: under pipefail, 'grep -q' exiting early can fail the pipeline.
    local help_text
    help_text=$(weka debug net ports --help 2> /dev/null || true)
    [[ ${help_text} == *--logs* ]] || return 0

    # 'weka cluster process' renamed its "id" column to "process" in 6.x.
    local process_col="id"
    if weka cluster process --no-header -o process &> /dev/null; then
        process_col="process"
    fi

    local process_id role
    while read -r process_id role _; do
        [[ -z ${process_id} || ${role} == MANAGEMENT ]] && continue
        weka debug net ports "${process_id}" --logs 2> /dev/null || true
    done < <(weka cluster process -F "hostname=${HOSTNAME_SHORT}" --no-header -o "${process_col},role" 2> /dev/null || true)
}

# Prints "hash" and/or "queue_affinity", one per line, for each mode the mlx5 PMD reported
# while setting up a TX queue. Prints nothing when it logged no mode: WEKA 6.x pins every
# TX queue itself, which skips that log line.
logged_lag_modes() {
    grep -oE 'BOND affinity_mode: MLX5_LAG_MODE_(HASH|TIS)' <<< "$1" \
        | sed -e 's/.*_HASH$/hash/' -e 's/.*_TIS$/queue_affinity/' \
        | sort -u || true
}

# Prints the mode the kernel applied to the LAG, read from mlx5 debugfs on the first bond
# member that exposes it. Needs root and a mounted debugfs; this check does not mount it.
debugfs_lag_mode() {
    local member pci mode
    for member in "$@"; do
        pci=$(basename "$(readlink -f "/sys/class/net/${member}/device")")
        # The read fails with EINVAL while the LAG is not active.
        if read -r mode 2> /dev/null < "/sys/kernel/debug/mlx5/${pci}/lag/port_sel_mode" && [[ -n ${mode} ]]; then
            echo "${mode}"
            return 0
        fi
    done
}

# Prints "active" or "disabled" from mlx5 debugfs, or nothing when debugfs is not mounted.
debugfs_lag_state() {
    local member pci state
    for member in "$@"; do
        pci=$(basename "$(readlink -f "/sys/class/net/${member}/device")")
        if read -r state 2> /dev/null < "/sys/kernel/debug/mlx5/${pci}/lag/state" && [[ -n ${state} ]]; then
            echo "${state}"
            return 0
        fi
    done
}

# Prints one line per bond member that is not carrying traffic: "<member> <reason>".
# With the default net.dpdk.link_down_check=false, WEKA's DPDK data path does not react to a
# member going down; peers stay on that member's port and only the NIC firmware's LAG remap
# keeps them alive. A member can also have link but not be bundled, which raises no alert.
# In /proc/net/bonding, an LACP port state with both collecting (0x10) and distributing (0x20)
# set is the one that carries traffic.
bond_member_problems() {
    local bond_file="/proc/net/bonding/$1" lacp=$2
    local line member="" section="" active_agg="" in_active_info=0
    local -A mii=() agg=() actor_state=()

    while IFS= read -r line; do
        case "${line}" in
            "Active Aggregator Info:"*) in_active_info=1 ;;
            "Slave Interface: "*) member=${line#Slave Interface: }; section=""; in_active_info=0 ;;
            "details actor lacp pdu:"*) section=actor ;;
            "details partner lacp pdu:"*) section=partner ;;
            *"Aggregator ID: "*)
                if [[ ${in_active_info} -eq 1 && -z ${active_agg} ]]; then
                    active_agg=${line##*: }
                elif [[ -n ${member} ]]; then
                    agg[${member}]=${line##*: }
                fi
                ;;
            "MII Status: "*) [[ -n ${member} ]] && mii[${member}]=${line##*: } ;;
            *"port state: "*) [[ -n ${member} && ${section} == actor ]] && actor_state[${member}]=${line##*: } ;;
        esac
    done < "${bond_file}"

    for member in "${!mii[@]}"; do
        if [[ ${mii[${member}]} != up ]]; then
            echo "${member} link is down (MII Status: ${mii[${member}]})"
        elif [[ ${lacp} -eq 1 && -n ${active_agg} && ${agg[${member}]:-} != "${active_agg}" ]]; then
            echo "${member} is not in the active LACP aggregator (member aggregator ${agg[${member}]:-none}, active ${active_agg})"
        elif [[ ${lacp} -eq 1 && -n ${actor_state[${member}]:-} ]] \
            && (( (actor_state[${member}] & 0x30) != 0x30 )); then
            echo "${member} is not collecting/distributing (LACP actor port state ${actor_state[${member}]})"
        fi
    done
}

if [[ -n "$BOND_INTERFACE" ]]; then
    # Version checks
    if verlt "4.3.3" "$CURRENT_WEKA_VERSION"; then
        :
    elif [[ "$CURRENT_WEKA_VERSION" == 4.* ]]; then
        if verlt "$CURRENT_WEKA_VERSION" "4.4.10.183"; then
            echo "WARN: This cluster does not contain the fixes from ${JIRA_REFERENCE}."
            echo " This could lead to unexpected loss of connectivity, particularly during link loss."
            RETURN_CODE=254
        fi

    elif [[ "$CURRENT_WEKA_VERSION" == 5.* ]]; then
        if verlt "$CURRENT_WEKA_VERSION" "5.1.0"; then
            echo "WARN: This cluster does not contain the fixes from ${JIRA_REFERENCE}."
            echo " This could lead to unexpected loss of connectivity, particularly during link loss."
            RETURN_CODE=254
        fi
    fi

    # Bonding mode check (1=active-backup, 4=LACP)
    if [[ "$BOND_MODE" != "1" && "$BOND_MODE" != "4" ]]; then
        echo "WARN: bond mode $BOND_MODE is not supported by WEKA -- only 1 (active-backup) and 4 (LACP)"
        RETURN_CODE=254
    fi

    # Xmit hash policy check
    HASH_POLICY=$(<"/sys/class/net/${BOND_INTERFACE}/bonding/xmit_hash_policy")
    if [[ "$HASH_POLICY" =~ layer2 ]]; then
        echo "WARN: xmit hash policy for ${BOND_INTERFACE} set to layer2."
        RETURN_CODE=254
    fi

    # Iterate over bond members ("slaves" is the kernel's sysfs name)
    read -ra MEMBER_LINKS < "/sys/class/net/${BOND_INTERFACE}/bonding/slaves"
    declare -A REQUESTED_LAG_MODES=() NIC_CHECKED=()
    for MEMBER_LINK in "${MEMBER_LINKS[@]}"; do
        # Check for virtual bond device. With hardware LAG active, the first PF's
        # infiniband/ directory holds mlx5_bond_N instead of mlx5_N.
        for IB_DEV in "/sys/class/net/${MEMBER_LINK}/device/infiniband/"*bond*; do
            [[ -e ${IB_DEV} ]] && VIRTUAL_BOND_FOUND=1
        done

        LAG_MODE_FILE="/sys/class/net/${MEMBER_LINK}/compat/devlink/lag_port_select_mode"
        if [[ -r ${LAG_MODE_FILE} ]]; then
            REQUESTED_LAG_MODES[$(<"${LAG_MODE_FILE}")]=1
        fi

        # NIC model detection, once per adapter (both ports share a PCI device).
        # The VPD "Product Name" can be missing (OEM cards), so the lspci device name is
        # matched too; it also names the ConnectX core of integrated BlueField NICs.
        PCI_DEV=$(basename "$(readlink -f "/sys/class/net/${MEMBER_LINK}/device")")
        [[ -n ${NIC_CHECKED[${PCI_DEV%.*}]:-} ]] && continue
        NIC_CHECKED[${PCI_DEV%.*}]=1
        NIC_MODEL=$(lspci -s "$PCI_DEV" -vv 2>/dev/null | grep -E "^${PCI_DEV#0000:} |Product Name" || true)
        NIC_MODEL=${NIC_MODEL//$'\n'/ }
        if [[ "$NIC_MODEL" =~ "Socket Direct" ]]; then
            echo "WARN: Socket Direct NICs (${MEMBER_LINK}) are unlikely to support bonding."
            RETURN_CODE=254
        elif [[ "$NIC_MODEL" =~ ConnectX-6\ Dx|ConnectX-7|ConnectX-8 ]]; then
            :
        elif [[ "$NIC_MODEL" =~ ConnectX-5|ConnectX-6($|[^ ]|\ [^L]) ]]; then
            # Verbs path, queue_affinity only: all data leaves on one port, so a bond only adds failover.
            if [[ "$BOND_MODE" == "4" ]]; then
                echo "WARN: ${MEMBER_LINK} is on a ConnectX-6 (non-Dx) or ConnectX-5 NIC (incl. CX-5 Ex and"
                echo " BlueField CX-5). On these NICs LACP is effectively failover only: WEKA traffic does"
                echo " not spread across both ports. Use active-backup (mode 1), or a CX-6 Dx/CX-7/CX-8 NIC."
                RETURN_CODE=254
            else
                echo "NOTE: ${MEMBER_LINK} is on a ConnectX-6 (non-Dx) or ConnectX-5 NIC; bonding on these"
                echo " NICs is effectively failover only, which matches the active-backup mode in use."
            fi
        else
            echo "WARN: Only ConnectX-6 Dx, ConnectX-7 and ConnectX-8 are officially supported for bonding (${MEMBER_LINK})."
            RETURN_CODE=254
        fi
    done

    mapfile -t MEMBER_PROBLEMS < <(bond_member_problems "${BOND_INTERFACE}" "$([[ "$BOND_MODE" == "4" ]] && echo 1 || echo 0)")
    for PROBLEM in "${MEMBER_PROBLEMS[@]}"; do
        echo "WARN: ${BOND_INTERFACE} member ${PROBLEM}; the bond is running without redundancy."
        RETURN_CODE=254
    done

    # A NIC's hardware LAG cannot span NICs. From 6.1, WEKA supports a bond across NICs
    # (multi-NIC LACP, WEKAPP-554387) by opening each member as its own DPDK port, as in HA,
    # so no mlx5_bond device is expected.
    if [[ ${#NIC_CHECKED[@]} -gt 1 ]]; then
        if verlt "$CURRENT_WEKA_VERSION" "6.1"; then
            echo "WARN: ${BOND_INTERFACE} members are on ${#NIC_CHECKED[@]} different NICs. Before WEKA 6.1, the"
            echo " members must be the two ports of one NIC; bonds across NICs need 6.1 or later."
            RETURN_CODE=254
        fi
    elif [[ $VIRTUAL_BOND_FOUND -eq 0 ]]; then # WEKAPP-571692
        RETURN_CODE=254
        if [[ $(debugfs_lag_state "${MEMBER_LINKS[@]}") == active ]]; then
            echo "WARN: the NIC formed a hardware LAG for ${BOND_INTERFACE}, but there is no mlx5_bond RDMA device."
            echo " WEKA's DPDK driver needs it to open the bond. Check that the mlx5_ib module is loaded."
        else
            echo "WARN: no hardware LAG found for ${BOND_INTERFACE} (no mlx5_bond device under"
            echo " /sys/class/net/<member>/device/infiniband/). Without it WEKA cannot use the bond. Check that:"
            echo "  - both of the NIC's ports are in the bond;"
            echo "  - the bond mode is 802.3ad or active-backup;"
            echo "  - the mlx5_ib module is loaded, and RoCE is enabled on both ports;"
            echo "  - SR-IOV/switchdev settings are not preventing LAG (see 'dmesg | grep -i lag')."
        fi
    fi

    # LAG port-selection mode only applies to hardware LAG (LACP)
    if [[ "$BOND_MODE" == "4" && $VIRTUAL_BOND_FOUND -eq 1 ]] && ! verlt "$CURRENT_WEKA_VERSION" "6.0"; then
        DPDK_LOGS=$(dpdk_port_logs)
        ALERTS=$(weka alerts --no-header 2> /dev/null || true)

        if [[ ${ALERTS} == *DPDKAggrPortFailure* ]]; then
            echo "WARN: DPDKAggrPortFailure alert is active: an LACP port failed to start in aggregated mode."
            echo " WEKA fell back to one bond port. Check 'weka alerts' for the affected host, and"
            echo " 'weka debug net ports <process-id> --logs'."
            RETURN_CODE=254
        fi

        # Both lines are PMD debug output; matching the bond device first proves the log
        # was captured at that verbosity, so a missing affinity line is meaningful.
        if [[ ${DPDK_LOGS} == *mlx5_bond* && ${DPDK_LOGS} != *"LAG Rx Port Affinity enabled"* ]]; then
            echo "WARN: the NIC does not report LAG RX port affinity for ${BOND_INTERFACE}."
            echo " WEKA cannot steer received traffic per bond port; expect a DPDKAggrPortFailure fallback."
            echo " Check the NIC firmware and driver versions."
            RETURN_CODE=254
        fi

    elif [[ "$BOND_MODE" == "4" && $VIRTUAL_BOND_FOUND -eq 1 ]]; then
        EXPECTED_LAG_MODE="hash"
        REQUESTED_LAG_MODE=$(IFS=,; echo "${!REQUESTED_LAG_MODES[*]}")
        mapfile -t DPDK_LAG_MODES < <(logged_lag_modes "$(dpdk_port_logs)")
        APPLIED_LAG_MODE=""
        APPLIED_LAG_SOURCE=""

        if [[ ${#DPDK_LAG_MODES[@]} -gt 1 ]]; then
            echo "WARN: WEKA processes on this host report different LAG modes (${DPDK_LAG_MODES[*]})."
            echo " Run 'weka debug net ports <process-id> --logs' per process and compare the 'BOND affinity_mode' lines."
            RETURN_CODE=254
        elif [[ ${#DPDK_LAG_MODES[@]} -eq 1 ]]; then
            APPLIED_LAG_MODE="${DPDK_LAG_MODES[0]}"
            APPLIED_LAG_SOURCE="WEKA DPDK port log"
        else
            APPLIED_LAG_MODE=$(debugfs_lag_mode "${MEMBER_LINKS[@]}")
            APPLIED_LAG_SOURCE="mlx5 debugfs"
        fi

        if [[ -n ${APPLIED_LAG_MODE} && ${APPLIED_LAG_MODE} != "${EXPECTED_LAG_MODE}" ]]; then
            echo "WARN: ${BOND_INTERFACE} LAG port-selection mode is ${APPLIED_LAG_MODE} (from ${APPLIED_LAG_SOURCE}); WEKA ${CURRENT_WEKA_VERSION} expects ${EXPECTED_LAG_MODE}."
            echo " Before 6.0, queue_affinity sends all WEKA data from each process out of one bond port."
            if [[ -n ${REQUESTED_LAG_MODE} ]]; then
                echo " Requested mode (compat/devlink/lag_port_select_mode): ${REQUESTED_LAG_MODE}."
                if [[ ${REQUESTED_LAG_MODE} == "${EXPECTED_LAG_MODE}" ]]; then
                    echo " The requested mode is already correct; it takes effect only once the bond is re-created."
                fi
            fi
            RETURN_CODE=254
        elif [[ -z ${APPLIED_LAG_MODE} && ${#DPDK_LAG_MODES[@]} -le 1 ]]; then
            echo "NOTE: could not determine the applied LAG mode for ${BOND_INTERFACE} (requested: ${REQUESTED_LAG_MODE:-unknown})."
            echo " Check with 'weka debug net ports <process-id> --logs' (pre-6.0) or"
            echo " 'cat /sys/kernel/debug/mlx5/<pci>/lag/port_sel_mode' with debugfs mounted."
        fi
    fi
fi

# Final output
if [[ $RETURN_CODE -eq 0 ]]; then
    echo "Bonding properly configured."
else
    echo "Recommended Resolution: Determine NIC compatibility with the bonding mode selected:"
    echo "https://docs.weka.io/planning-and-installation/prerequisites-and-compatibility#networking-ethernet"
fi

exit $RETURN_CODE
