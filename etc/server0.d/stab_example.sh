#!/bin/bash
# Example script included to run specific test

# Return codes are as follows: 0 = Success, >0 = Failure, 254= Warning, 255 = Fatal failure (stop all tests)

DESCRIPTION="Hello World Script which will fail.."

# Put your stuff here
write_log "Script name: $0"
write_log "Hello world!"
ret=1

exit $ret
