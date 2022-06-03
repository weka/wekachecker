#!/usr/bin/env python3

import json
import argparse
import sys
import os

def process_json(infile, outfile, print_stdout=True):
    returnCodes = {0: "PASS", 1: "FAIL", 254: "WARN", 255: "HARDFAIL"}

    with open( infile ) as fp:
        results = json.load( fp )
    with open (outfile, 'w') as of:
        for scriptname, server_dict in results.items():
            for server, test_results in server_dict.items():
                scriptname = os.path.basename(scriptname)
                returnCode = test_results[0]
                msg = test_results[1]
                result = returnCodes[returnCode]
                if returnCode != 0:
                    m = f"{scriptname}: {server}: {result}: {msg}\n"
                    if print_stdout:
                        print(m)
                    of.write(m)

def main():
    # parse arguments
    parser = argparse.ArgumentParser(description='Process wekachecker json output into text file')
    parser.add_argument('json_input_file', nargs='?', default='test_results.json', type=str, 
        help='json file that was created by wekachecker (default: "test_results.json")')
    parser.add_argument('-o', dest='outfile', default='test_results.txt', type=str, 
        help='output file name (default: "test_results.txt")')

    args = parser.parse_args()
    process_json(args.json_input_file, args.outfile)

if __name__ == "__main__":
    main()