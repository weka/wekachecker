#!/usr/bin/env python3

import json
import argparse
import sys
import os

# parse arguments
progname=sys.argv[0]
parser = argparse.ArgumentParser(description='Execute server cert scripts on servers')
parser.add_argument('json_input_file', metavar='json_input_file', type=str, help='json file that was created by wekachecker')

args = parser.parse_args()

returnCodes = {0: "PASS", 1: "FAIL", 254: "WARN", 255: "HARDFAIL"}

with open( args.json_input_file ) as fp:
    results = json.load( fp )

    for scriptname, server_dict in results.items():
        for server, test_results in server_dict.items():
            #print( "test_results:" )
            #print( test_results )
            scriptname = os.path.basename(scriptname)
            returnCode = test_results[0]
            result = returnCodes[returnCode]
            if returnCode != 0:
                print( scriptname + ": " + server + ": " + result + ': ' + test_results[1] )
