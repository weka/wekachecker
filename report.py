#!/usr/bin/env python3

import json
import argparse
import glob
import sys
import logging

import os
from contextlib import contextmanager


# parse arguments
progname=sys.argv[0]
parser = argparse.ArgumentParser(description='Execute server cert scripts on servers')
parser.add_argument('json_input_file', metavar='json_input_file', type=str, help='json file that was created by wekachecker')

args = parser.parse_args()

with open( args.json_input_file ) as fp:
    results = json.load( fp )

    for directory, server_dict in results.items():
        for server, tests_dict in server_dict.items():
            #print( "tests_dict:" )
            #print( tests_dict )
            for test, test_results in tests_dict.items():
                #print( "test_results:" )
                #print( test_results )
                if test_results[0] != 0:
                    print( directory + ": " + server + ": " + test + ": " + test_results[1] )
