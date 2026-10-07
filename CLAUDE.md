# wekachecker2 - Jira Creation Task

## What this is

Creating Jira issues in WEKAPP for each `scripts.d/ta/` script that checks a condition
which could instead be detected and alerted on by the WEKA product itself.

The full plan is in `jira-plan.md`.

---

## Jira configuration

| Field | Value |
|-------|-------|
| Atlassian cloud ID | `0b7ca77e-5961-4878-bb06-ce25499c17ac` |
| Project | `WEKAPP` |
| Issue type | `Manual Bug` |
| Priority | `Major` |
| Title format | `tatool-automatic | Raise alert if ...` |

---

## Rules

- 7-bit ASCII only in all Jira text, and in tests themselves
- Maximal brevity
- Do not use "confirmed bug" or any language that sounds overconfident about root cause
- Each Jira must follow this exact description format:
- Suggested alerts should include a single tag (multiple words, no spaces) followed by a clear human-readable explanation. E.g. "InterfaceMTUMismatch   The Interfaces <X> and <Y> on process <Z> (host abc123) have mismatched MTUs"
- Where possible, for tests, include simple tests that can be run to verify the existence of the issue. Prefer checks that read sysfs rather than use external tools. You can use `ssh root@cstb08` to test checks
- Before presenting any draft, check whether the product already has an alert covering the condition by searching the product source at `/Users/j/git-repos/wekapp` (grep the alert definitions). If an existing alert covers it, default to suggesting **skip** with the reason, rather than drafting a redundant ticket
- Do NOT check docs for this purpose, and do not skip a check merely because docs tell users to configure something correctly -- alerts should exist EVEN IF the user has NOT followed docs
- Where possible, find customer problems that ended up as Jiras and link the created Jira to those customer cases with link type "Evidence for customer cases"
- NEVER set or modify "Max field priority" (`customfield_15354`) on any Jira. Use it only in JQL as a signal for finding customer cases worth linking as evidence (e.g. `"Max field priority" is not EMPTY`)
- Jira mechanics discovered: there is NO "Evidence for customer cases" link type in this instance; use "Relates" links. The createIssueLink comment parameter posts onto the LINKED (customer case) issue under the user's name, not onto our ticket (discovered via WEKAPP-639825 comment 13318784)
- Any comment placed on the original motivating/customer Jira MUST be prefixed with: "Automated comment: tatool-automatic breadcrumb comment." followed by the evidence text

```
# Problem Description

<blank line>
...

# Next Steps / Request of R&D

<blank line>
...

# Details of Tests

<blank line>
...

# Suggested alert text

<blank line>
...
```

Headers must be Markdown H1 with a blank line after each.

---

## Resolved decisions

- Title prefix: `tatool-automatic` (separator is ` | ` not `:`)
- `740_mlx_settings.sh` IS included -- mlxconfig will be added to the product
- Low-priority scripts ignored per user instruction: `370`, `390`, `755`
- Duplicate check completed: `060_clockdiff`, `130_checkntp`, `520_bucket_and_process_uptime`, `540_check_for_obs_in_scarce_mode`, `930_leader_iteration_too_slow` were all searched in WEKAPP and no conflicting Manual Bug Jiras were found; all proceed

## Example Jiras

- WEKAPP-619223: https://wekaio.atlassian.net/browse/WEKAPP-619223 (original format example, component: Platform / Network)
- WEKAPP-630612: https://wekaio.atlassian.net/browse/WEKAPP-630612 (first created Jira in this batch; use as format reference)

---

## Workflow

Present one Jira at a time. Wait for one of:
- **approve** - create it, then move to next
- **skip** - discard, move to next
- **edit: [changes]** - apply changes, re-present, wait again

Always link the created Jira after creation.

**Important:** If a script is marked **IN REVIEW**, re-draft its Jira from scratch by reading the script, then present it for approval. Do not assume it was approved.

---

## Progress

**BATCH COMPLETE 2026-07-07.** All 100 scripts decided: 57 rows Created (some sharing tickets via folding), 43 rows Skipped with reasons recorded inline. No Pending rows remain.

| # | Script | Component | Status | Jira |
|---|--------|-----------|--------|------|
| 1 | `010_ping.sh` | Platform / Network | Created | [WEKAPP-630612](https://wekaio.atlassian.net/browse/WEKAPP-630612) |
| 2 | `015_mtu.sh` | Platform / Network | Created | [WEKAPP-639919](https://wekaio.atlassian.net/browse/WEKAPP-639919) |
| 3 | `030_dup_uuid_check.sh` | Control | Created | [WEKAPP-639920](https://wekaio.atlassian.net/browse/WEKAPP-639920) |
| 4 | `060_clockdiff.sh` | Control | Skipped | ClockSkew alert exists; rest is pre-install |
| 5 | `105_selinux.sh` | Platform | Created | [WEKAPP-639921](https://wekaio.atlassian.net/browse/WEKAPP-639921) (evidence: WEKAPP-538034) |
| 6 | `110_checkos.sh` | Control | Created | [WEKAPP-639934](https://wekaio.atlassian.net/browse/WEKAPP-639934) (evidence: WEKAPP-287461) |
| 7 | `115_freespace.sh` | Control / Agent | Skipped | LowDiskSpaceEvent exists (verified in WEKAPP-577223); sizing is pre-install |
| 8 | `120_freeram.sh` | Platform | Created | [WEKAPP-639936](https://wekaio.atlassian.net/browse/WEKAPP-639936) (evidence: WEKAPP-639825) |
| 9 | `125_checkinternet.sh` | Platform / Network | Skipped | Cloud connectivity already alerted ("cloud: unhealthy") |
| 10 | `130_checkntp.sh` | Control | Created | [WEKAPP-639937](https://wekaio.atlassian.net/browse/WEKAPP-639937) (evidence: WEKAPP-569709, WEKAPP-585795) |
| 11 | `135_checkdns.sh` | Control | Created | [WEKAPP-639938](https://wekaio.atlassian.net/browse/WEKAPP-639938) (evidence: WEKAPP-560576, WEKAPP-624841) |
| 12 | `140_checkiptables.sh` | Control | Created | [WEKAPP-639940](https://wekaio.atlassian.net/browse/WEKAPP-639940) |
| 13 | `145_checkwekapackages.sh` | Control / Agent | Created | [WEKAPP-639941](https://wekaio.atlassian.net/browse/WEKAPP-639941) (evidence: WEKAPP-553235) |
| 14 | `150_htcputest.sh` | Platform | Created | [WEKAPP-639942](https://wekaio.atlassian.net/browse/WEKAPP-639942) |
| 15 | `155_checkkernel.sh` | Platform | Skipped | User decision: kernel-compat checks do not belong in product |
| 16 | `160_checkaes.sh` | Platform | Skipped | Agent hard-enforces AES at startup (CPUFlagMissingError) |
| 17 | `180_numabalancing.sh` | Platform | Skipped | BackendNumaBalancingEnabled alert exists |
| 18 | `185_memtest.sh` | Platform | Created | [WEKAPP-639995](https://wekaio.atlassian.net/browse/WEKAPP-639995) |
| 19 | `190_checkxfs.sh` | Platform | Skipped | Agent has fallback + explicit error; packages covered by WEKAPP-639941 |
| 20 | `195_ofed.sh` | Platform / Network | Skipped | OfedVersions alert deliberately removed (WEKAPP-263390) |
| 21 | `200_checkiommu.sh` | Platform | Skipped | Version-pinned to WEKAPP-323895 (4.1.2-4.2.2) |
| 22 | `210_checksquashfs.sh` | Control / Agent | Created | [WEKAPP-639997](https://wekaio.atlassian.net/browse/WEKAPP-639997) |
| 23 | `215_checktmpmount.sh` | Control | Created | [WEKAPP-639998](https://wekaio.atlassian.net/browse/WEKAPP-639998) |
| 24 | `220_checknvmebus.sh` | Platform / SSD | Skipped | Exact ask rejected by R&D (WEKAPP-145555) |
| 25 | `223_checknvmelba.sh` | Platform / SSD | Created | [WEKAPP-640001](https://wekaio.atlassian.net/browse/WEKAPP-640001) |
| 26 | `225_checksecureboot.sh` | Platform | Skipped | Secure Boot is supported (module signing, skip_lockdown) |
| 27 | `250_irqconflict.sh` | Platform | Created | [WEKAPP-640003](https://wekaio.atlassian.net/browse/WEKAPP-640003) (evidence: WEKAPP-237067) |
| 28 | `260_compare_dpdk_gateways.sh` | Platform / Network | Created | [WEKAPP-640004](https://wekaio.atlassian.net/browse/WEKAPP-640004) |
| 29 | `270_weka_local_resources_gateways.sh` | Platform / Network | Skipped | Folded into WEKAPP-640004 |
| 30 | `280_check_only_one_weka_version.sh` | Control | Created | [WEKAPP-640006](https://wekaio.atlassian.net/browse/WEKAPP-640006) |
| 31 | `290_check_traces_free_space.sh` | Control | Created | [WEKAPP-640007](https://wekaio.atlassian.net/browse/WEKAPP-640007) |
| 32 | `330_nfs_v4_ip_address_failover.sh` | Interfaces / NFS / Ganesha | Skipped | User decision: floating IPs are a design choice; WEKAPP-298483 Won't Fix |
| 33 | `360_disparate_drive_write_latencies.sh` | Platform / SSD | Created | [WEKAPP-640014](https://wekaio.atlassian.net/browse/WEKAPP-640014) (evidence: WEKAPP-329809) |
| 34 | `380_check_leader_is_running_on_drive_process.sh` | Control | Skipped | canBeLeadership already requires a DRIVES node |
| 35 | `400_s3_using_etcd.sh` | Interfaces / S3-FE | Skipped | Version-pinned etcd-to-KWAS migration (4.0-4.2.0) |
| 36 | `410_nvme_controllers_with_invalid_irq.sh` | Platform / SSD | Skipped | Folded into WEKAPP-640003 |
| 37 | `420_check_cross-numa_zone_memory_balance.sh` | Platform | Created | [WEKAPP-640015](https://wekaio.atlassian.net/browse/WEKAPP-640015) (evidence: WEKAPP-621687) |
| 38 | `430_nvme_used_capacity_vs_maximum.sh` | Platform / SSD | Skipped | BucketCapacityExhausting + SSDCapacityTooHigh alerts exist |
| 39 | `440_hostnames_rfc952.sh` | Control | Created | [WEKAPP-640016](https://wekaio.atlassian.net/browse/WEKAPP-640016) |
| 40 | `450_custom_ca_certs.sh` | Platform | Skipped | Legacy SSL_CERT_FILE workaround; moot with native CA bundles |
| 41 | `460_ip_source-based_routing.sh` | Platform / Network | Created | [WEKAPP-640017](https://wekaio.atlassian.net/browse/WEKAPP-640017) (evidence: WEKAPP-360289; related: WEKAPP-619223) |
| 42 | `470_number_of_numa_domains.sh` | Platform | Skipped | TooManyNumaNodes enforced in product; rest version-pinned |
| 43 | `480_check_weka_agent.sh` | Control / Agent | Created | [WEKAPP-640018](https://wekaio.atlassian.net/browse/WEKAPP-640018) |
| 44 | `490_ip_route_metrics.sh` | Platform / Network | Skipped | Weak heuristic; harmful case covered by WEKAPP-640017 |
| 45 | `500_sysctl_rp_filter.sh` | Interfaces / NFS / Ganesha + Interfaces / SMBW | Created | [WEKAPP-640054](https://wekaio.atlassian.net/browse/WEKAPP-640054) (evidence: WEKAPP-523530, WEKAPP-628672) |
| 46 | `510_check_for_noprefixroute.sh` | Platform / Network | Skipped | User decision: probably does not belong in the product yet |
| 47 | `520_bucket_and_process_uptime.sh` | Control | Skipped | NodeNetworkUnstable covers restart churn; raw restarted-recently alert too noisy |
| 48 | `530_high_drive_read_ssd_ratio.sh` | Platform / SSD | Skipped | Workload-dependent heuristic (read amplification may be legitimate); reconsider under 782 statistical thresholds |
| 49 | `540_check_for_obs_in_scarce_mode.sh` | Filesystem / OBS | Created | [WEKAPP-640059](https://wekaio.atlassian.net/browse/WEKAPP-640059) (evidence: WEKAPP-376458) |
| 50 | `550_iptables_nats_local_traffic.sh` | Platform / Network | Skipped | Folded into WEKAPP-639940 (NAT-table check added to its scope) |
| 51 | `560_check_for_swap.sh` | Platform | Skipped | Swap presence is legitimate; harmful condition (WEKA swapping) covered by WEKAPP-640067 |
| 52 | `570_does_weka_use_swap.sh` | Platform | Created | [WEKAPP-640067](https://wekaio.atlassian.net/browse/WEKAPP-640067) |
| 53 | `580_weka_version_available_everywhere.sh` | Control | Skipped | Covered by BackendVersionsMismatch + ClientVersionsMismatch alerts |
| 54 | `590_single_dns_entry.sh` | Interfaces / SMBW | Created | [WEKAPP-640072](https://wekaio.atlassian.net/browse/WEKAPP-640072) |
| 55 | `610_nfs_aliases_sbr.sh` | Interfaces / Floating IP | Created | [WEKAPP-640074](https://wekaio.atlassian.net/browse/WEKAPP-640074) (related: WEKAPP-640017) |
| 56 | `620_same_mtu_across_nics.sh` | Platform / Network | Created | [WEKAPP-640076](https://wekaio.atlassian.net/browse/WEKAPP-640076) (evidence: WEKAPP-316504) |
| 57 | `630_opt_weka_exists_but_not_mounted.sh` | Control / Agent | Created | [WEKAPP-640079](https://wekaio.atlassian.net/browse/WEKAPP-640079) |
| 58 | `635_loopback_fs_free_space.sh` | Control / Agent | Skipped | LowDiskSpace alert/event covers mounted loopbacks (verified in WEKAPP-577223); offline .loop files fail explicitly at start |
| 59 | `640_opt_weka_is_not_symlink.sh` | Control / Agent | Created | [WEKAPP-640094](https://wekaio.atlassian.net/browse/WEKAPP-640094) |
| 60 | `650_firewall_check_quick.sh` | Platform / Network | Skipped | Intra-cluster connectivity continuously monitored (NodeDisconnected/PartiallyConnectedNode); firewall cause covered by WEKAPP-639940 |
| 61 | `660_hugepages_check.sh` | Platform | Skipped | Script itself says not indicative; harmful outcome covered by PartialHugepageAllocation alert |
| 62 | `670_crowdstrike_check.sh` | Platform | Created | [WEKAPP-640106](https://wekaio.atlassian.net/browse/WEKAPP-640106) (evidence: WEKAPP-491668) |
| 63 | `670_nm_ignore_carrier.sh` | Platform / Network | Created | [WEKAPP-640111](https://wekaio.atlassian.net/browse/WEKAPP-640111) (evidence: WEKAPP-392845) |
| 64 | `680_redundant_weka_overrides.sh` | Control | Created | [WEKAPP-640113](https://wekaio.atlassian.net/browse/WEKAPP-640113) |
| 65 | `690_auto_core_in_mcb.sh` | Control | Created | [WEKAPP-640120](https://wekaio.atlassian.net/browse/WEKAPP-640120) |
| 66 | `710_no_spaces_in_cluster_name.sh` | Control | Created | [WEKAPP-640124](https://wekaio.atlassian.net/browse/WEKAPP-640124) |
| 67 | `720_low_compute_ram_to_ssd.sh` | Control | Skipped | HighSSDToRAMRatio alert covers this (severity tuning at most) |
| 68 | `730_large_drives.sh` | Platform / SSD | Skipped | Version-pinned to pre-4.1.2 (WEKAPP-324010); moot on current versions |
| 69 | `740_ensure_cgroups_v1_with_protocols.sh` | Platform | Skipped | NoCgroupsConfigured alert exists; v1-only requirement superseded (product supports v1/v2); see 875 for current cgroup check |
| 70 | `740_mlx_settings.sh` | Platform / Network | Created | [WEKAPP-640665](https://wekaio.atlassian.net/browse/WEKAPP-640665) (evidence: WEKAPP-524442) |
| 71 | `765_process_network_mode.sh` | Platform / Network | Skipped | UdpModePerformanceWarning covers UDP backends; port-registration check is internal state whose symptoms hit connectivity alerts |
| 72 | `775_dup_arp_check.sh` | Platform / Network | Created | [WEKAPP-640256](https://wekaio.atlassian.net/browse/WEKAPP-640256) (evidence: WEKAPP-628083, WEKAPP-618993) |
| 73 | `780_statistical_outlier.sh` | Platform / Network | Created | [WEKAPP-640261](https://wekaio.atlassian.net/browse/WEKAPP-640261) (combined with 782) |
| 74 | `782_statistical_thresholds.sh` | Platform / Network | Created | [WEKAPP-640261](https://wekaio.atlassian.net/browse/WEKAPP-640261) (combined with 780) |
| 75 | `785_asymmetric_mtu.sh` | Platform / Network | Created | [WEKAPP-640262](https://wekaio.atlassian.net/browse/WEKAPP-640262) (evidence: WEKAPP-438140) |
| 76 | `790_raft_agents.sh` | Control | Skipped | Product enforces agents-per-node limit (TooManyAgentsPerNodeException in constraints.d) at clustering operations |
| 77 | `795_netmask_mismatch.sh` | Platform / Network | Created | [WEKAPP-640266](https://wekaio.atlassian.net/browse/WEKAPP-640266) |
| 78 | `805_bonding_check.sh` | Platform / Network | Created | [WEKAPP-640267](https://wekaio.atlassian.net/browse/WEKAPP-640267) (evidence: WEKAPP-571692, WEKAPP-539450) |
| 79 | `810_use_only_readcache_for_protocols.sh` | Interfaces / NFS / Ganesha + Interfaces / SMBW | Created | [WEKAPP-640268](https://wekaio.atlassian.net/browse/WEKAPP-640268) (evidence: WEKAPP-444847) |
| 80 | `815_no_spaces_in_fs_name.sh` | Interfaces / S3-FE | Created | [WEKAPP-640269](https://wekaio.atlassian.net/browse/WEKAPP-640269) (related: WEKAPP-640124) |
| 81 | `825_ha_mgmt_ip.sh` | Control | Created | [WEKAPP-640270](https://wekaio.atlassian.net/browse/WEKAPP-640270) |
| 82 | `835_s2o_unmigrated.sh` | Filesystem / Snap2Obj | Created | [WEKAPP-640271](https://wekaio.atlassian.net/browse/WEKAPP-640271) |
| 83 | `845_mem_alloc.sh` | Platform | Created | [WEKAPP-640302](https://wekaio.atlassian.net/browse/WEKAPP-640302) (related: WEKAPP-639936) |
| 84 | `850_heartbeat_gt_cluster_lease.sh` | Control | Created | [WEKAPP-640319](https://wekaio.atlassian.net/browse/WEKAPP-640319) |
| 85 | `855_nfsw_fips_sanity.sh` | Interfaces / Floating IP | Created | [WEKAPP-640407](https://wekaio.atlassian.net/browse/WEKAPP-640407) (evidence: WEKAPP-471021; related: WEKAPP-640256, WEKAPP-640074) |
| 86 | `865_infiniband_lid_mismatch.sh` | Platform / Network | Skipped | Underlying bug WEKAPP-422897 Fixed in V4.4 (released 2025-07-20); check moot on current versions |
| 87 | `870_wekafs_requires_netdev.sh` | Control / Agent | Created | [WEKAPP-640466](https://wekaio.atlassian.net/browse/WEKAPP-640466) |
| 88 | `875_cgroup_validation.sh` | Control / Agent | Created | [WEKAPP-640469](https://wekaio.atlassian.net/browse/WEKAPP-640469) (evidence: WEKAPP-482528) |
| 89 | `880_all_mdadm_devices_good.sh` | Control / Agent | Skipped | User decision: extremely rare for backends to use mdadm; left for now (draft exists in session history if revisited) |
| 90 | `885_nfsw_resources.sh` | Interfaces / NFS / Ganesha | Created | [WEKAPP-640627](https://wekaio.atlassian.net/browse/WEKAPP-640627) (evidence: WEKAPP-546698) |
| 91 | `890_hot_spare_capacity.sh` | Control | Skipped | NoHotSpareFailureDomains (WARNING) + NotEnoughSSDCapacity (MAJOR) cover this; fill-level math is severity refinement |
| 92 | `900_check_link_speeds.sh` | Platform / Network | Created | [WEKAPP-640650](https://wekaio.atlassian.net/browse/WEKAPP-640650) |
| 93 | `910_disparate_bucket_fill_level.sh` | Control | Skipped | RAIDCapacityExhaustion (MAJOR) covers full buckets; imbalance self-corrected by automatic rebalancing |
| 94 | `915_rdma_network_errors.sh` | Platform / Network | Skipped | Folded into WEKAPP-640261 (RDMA hard-error counters added to its scope) |
| 95 | `920_nfs_tcp_connections.sh` | Interfaces / NFS / Ganesha | Skipped | Folded into WEKAPP-640627 (failover projection + single-host SPOF added to its scope) |
| 96 | `920_nvme_bs.sh` | Platform / SSD | Skipped | Folded into WEKAPP-640001 (mixed block-size warning added to its scope) |
| 97 | `925_no_default_obs_configs.sh` | Interfaces / S3-FE | Skipped | User decision: default OBS tuning is often fine (script itself says so); advisory only, not alertable |
| 98 | `930_leader_iteration_too_slow.sh` | Control | Created | [WEKAPP-640654](https://wekaio.atlassian.net/browse/WEKAPP-640654) (evidence: WEKAPP-513421) |
| 99 | `935_container_resource_alloc.sh` | Control | Created | [WEKAPP-640664](https://wekaio.atlassian.net/browse/WEKAPP-640664) |
| 100 | `945_obs_conn_check.sh` | Interfaces / S3-FE | Skipped | NodeTieringConnectivity (MAJOR) covers OBS connectivity; RTT check experimental, 5xx stats hedged (could join WEKAPP-640261 later) |
| 101 | `555_nf_conntrack.sh` | Platform / Network | New check ([PR #222](https://github.com/weka/wekachecker/pull/222)) | References existing [WEKAPP-639825](https://wekaio.atlassian.net/browse/WEKAPP-639825); no new Jira (direction is Jira-to-script, not script-to-alert) |

## Skipped (no Jira)

| Script | Reason |
|--------|--------|
| `000_log_ta-tool_run.sh` | Not a check |
| `020_ssh.sh` | Cannot be in-product (external SSH test) |
| `370_version_specific_checks.sh` | All referenced bugs fixed; ignored per user instruction |
| `390_data_folder.sh` | Bug fixed, check moot; ignored per user instruction |
| `700_wekapp351707.sh` | Version-pinned to fixed bug |
| `755_wekapp424920_smbw_mask.sh` | Won't Fix, version-specific; ignored per user instruction |
| `950_wekanode_cpu_affinity.sh` | Won't Fix, empty script |
| `060_clockdiff.sh` | Product already has ClockSkew alert; remaining use is pre-install where no product is present |
| `115_freespace.sh` | Product already emits LowDiskSpaceEvent (verified in WEKAPP-577223); sizing aspect is pre-install; partition aspect covered by 630/640 |
| `125_checkinternet.sh` | Product already alerts on Weka Home cloud connectivity ("cloud: unhealthy" in weka status); general internet reachability is pre-install only |
| `155_checkkernel.sh` | User decision: kernel-compatibility checks do not belong in the product |
| `160_checkaes.sh` | Agent already hard-enforces AES at startup (daemon.d CPUFlagMissingError); condition cannot develop on a running host |
| `180_numabalancing.sh` | Product already has BackendNumaBalancingEnabled alert (WARNING) covering exactly this |
| `190_checkxfs.sh` | Agent has explicit fallback + error for missing mkfs.xfs (agent/os/loop.d); proactive package presence covered by WEKAPP-639941 |
| `195_ofed.sh` | R&D deliberately removed the OfedVersions alert (WEKAPP-263390); version matrix falls under the kernel-check ruling |
| `200_checkiommu.sh` | Version-pinned to WEKAPP-323895 (susceptible only 4.1.2-4.2.2); moot on current versions |
| `220_checknvmebus.sh` | Exact ask (error on drive add for VMD device) was rejected by R&D in WEKAPP-145555 |
| `225_checksecureboot.sh` | Agent has explicit Secure Boot support (lockdown detection, module signing, skip_lockdown); blanket alert would be wrong |
| `270_weka_local_resources_gateways.sh` | Folded into WEKAPP-640004 (missing-gateway case added to its scope) |
| `330_nfs_v4_ip_address_failover.sh` | User decision: floating IPs with NFSv4 is a product design choice (underlying WEKAPP-298483 is Won't Fix); nothing actionable |
| `380_check_leader_is_running_on_drive_process.sh` | Product enforces by construction: canBeLeadership requires a DRIVES node (weka/cluster/resources/types.d) |
| `400_s3_using_etcd.sh` | Version-pinned to 4.0-4.2.0 etcd-to-KWAS migration; moot on current versions |
| `410_nvme_controllers_with_invalid_irq.sh` | Folded into WEKAPP-640003 (invalid IRQ routing added as second diagnosable cause) |
| `430_nvme_used_capacity_vs_maximum.sh` | Covered by BucketCapacityExhausting (90% placements) and SSDCapacityTooHigh alerts |
| `450_custom_ca_certs.sh` | Legacy SSL_CERT_FILE workaround detection (KB 1179); moot on versions with native CA bundle support |
| `470_number_of_numa_domains.sh` | Product hard-enforces limit (TooManyNumaNodes in hugepages.d); rest is version-pinned thresholds |
| `490_ip_route_metrics.sh` | Weak heuristic with legitimate configs; harmful outcome covered by WEKAPP-640017 route-path verification |
| `510_check_for_noprefixroute.sh` | User decision: probably does not belong in the product yet |
