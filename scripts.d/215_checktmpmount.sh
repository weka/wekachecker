#!/bin/bash

DESCRIPTION="Check for /tmp noexec mount"
SCRIPT_TYPE="parallel"


mount | grep "on /tmp " | grep noexec &> /dev/null
if [ $? == 0 ]; then
    write_log "ERROR: /tmp is mounted with noexec on `hostname`"
    exit 1
fi

exit 0
