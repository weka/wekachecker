#!/usr/bin/env python

#
# imports
#
import argparse
import sys

###################################################################################################################
#
# main()
#
# Return codes are as follows: 0 = Success, >0 = Failure, 255 = Fatal failure (stop all tests)

# Parse arguments
parser = argparse.ArgumentParser()
parser.add_argument("host", nargs="+", help="a hostname or IP address", type=str )
args = parser.parse_args()
hosts = args.host   # makes a list of hostnames/ips


description="Hello World Script which will fail.."


print description

# Say hello

print "Hello, World!"
sys.exit( 1 )   # return failure
