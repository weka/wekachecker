#!/bin/bash

DESCRIPTION="Check for XFS FS type installed"
SCRIPT_TYPE="parallel"

which mkfs.xfs &> /dev/null
if [ $? == 1 ]; then
    write_log "ERROR: XFS not installed"
    exit 255
else
	write_log "XFS installed"
	ret="0"
fi

exit $ret
