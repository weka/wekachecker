#!/bin/bash

DESCRIPTION="Check NVMe LBA format..."
SCRIPT_TYPE="parallel"

# Array containing all available LBA formats per array
declare -A namespace_lba_formats

# Functions to extract the above, as Bash does not supported nested associative
# arrays
get_lba_format_in_use() {
	echo "${namespace_lba_formats["$1"]}" | awk '/in use/ { print $2 }'
}

get_metadata_size() {
	local ms=$(echo "${namespace_lba_formats["$1"]}" | awk "\$2 == \"$2\" { print \$4 }")
	echo "${ms#ms:}"
}

get_data_size() {
	local lbads=$(echo "${namespace_lba_formats["$1"]}" | awk "\$2 == \"$2\" { print \$5 }")
	echo "${lbads#lbads:}"
}

get_relative_performance() {
	local rp=$(echo "${namespace_lba_formats["$1"]}" | awk "\$2 == \"$2\" { print \$6 }")
	echo "${rp#rp:}"
}

# Array containing current LBA format in use
declare -A namespace_lba_format_in_use

# Array containing current metadata size, in bytes
declare -A namespace_current_metadata_size

# Array containing current data size per array, in bytes
declare -A namespace_current_data_size

# Array containing current relative performance setting
declare -A namespace_current_relative_performance

rc=0

# Populate arrays
for namespace in /dev/nvme*n*; do
	namespace_lba_formats["$namespace"]=$(sudo nvme id-ns "$namespace" | awk '/^lbaf/')
	namespace_lba_format_in_use["$namespace"]=$(get_lba_format_in_use "$namespace")
	namespace_current_metadata_size["$namespace"]=$(get_metadata_size "$namespace" "${namespace_lba_format_in_use["$namespace"]}")
	namespace_current_data_size["$namespace"]=$(get_data_size "$namespace" "${namespace_lba_format_in_use["$namespace"]}")
	namespace_current_relative_performance["$namespace"]=$(get_relative_performance "$namespace" "${namespace_lba_format_in_use["$namespace"]}")
done

# WARN checks
## Block size differences
unified_block_size=$(for namespace in ${!namespace_current_data_size[@]}; do
	echo "${namespace_current_data_size["$namespace"]}"
done | sort -u | wc -l)
if [ "$unified_block_size" -ne 1 ]; then
	block_size_table=$(for namespace in /dev/nvme*n*; do
		printf "  %14s %6s\n" "$namespace" "$((2**"${namespace_current_data_size["$namespace"]}"))"
	done)
	write_log
	write_log 'Block size mismatch among NVMe devices:'
	write_log "$block_size_table"
	write_log
	rc=254
fi

# FAIL checks
for namespace in /dev/nvme*n*; do
	ms=${namespace_current_metadata_size["$namespace"]}
	lbads=${namespace_current_data_size["$namespace"]}
	rp=${namespace_current_relative_performance["$namespace"]}

	if [ "$ms" -ne 0 ]; then
		write_log "$namespace: Metadata size ($ms) is greater than 0"
		rc=1
	fi

	if [ "$lbads" -gt 12 ]; then
		write_log "$namespace: Block size ($lbads) is larger than 4K"
		rc=1
	fi

	if [ "$rp" -ne 0 ]; then
		write_log "$namespace: Relative performance ($rp) is not set to 0 (Best)"
		rc=1
	fi
done

if [ "$rc" -ne 0 ]; then
	write_log
	write_log 'To resolve the above issue(s), reformat the NVMe namespace(s) (assuming that'
	write_log 'it is intended to be a WEKA drive) using an LBA format with:'
	write_log
	write_log '    - Metadata size of 0;'
	write_log '    - Data size of 4K or lower, matching all namespaces if possible;'
	write_log '    - Relative performance of 0 (Best).'
	write_log
	write_log 'Changing the NVMe namespace as necessary, see the output of the following'
	write_log 'for the available LBA formats:'
	write_log
	write_log "    sudo nvme id-ns /dev/nvme0n1 -H | grep '^LBA Format'"
	write_log
	write_log 'And run the following command to reformat after selecting an LBA format:'
	write_log
	write_log '    sudo nvme format --lbaf=1 /dev/nvme0n1'
	write_log
	write_log 'Note that data will be lost when reformatting. It is strongly recommended'
	write_log 'that the LBA format of all WEKA NVMe devices match if possible.'
fi

exit "$rc"