#!/bin/bash

DESCRIPTION="Check for XFS FS type installed"
SCRIPT_TYPE="parallel"

which mkfs.xfs &> /dev/null
if [ $? == 1 ]; then
    write_log "ERROR: XFS not installed"
    exit 255
fi

exit 0
