#!/usr/bin/env python3

import argparse
import json
import sys


def process_json(infile, outfile):
    returnCodes = {0: "PASS", 1: "*FAIL", 127: "SCRIPT ERROR", 254: "WARN", 255: "*HARDFAIL"}
    indent = ' ' * 6
    with open(infile) as fp:
        results = json.load(fp)
    with (open(outfile, 'w') if outfile != '-' else sys.stdout) as of:
        for scriptname_description, server_dict in results.items():
            scriptname, description = scriptname_description.split(":")
            first = True
            header = f"\n{scriptname}:\n  {description}\n"
            for server, test_results in server_dict.items():
                serverstr = f" {server + ': ':<17}"
                returnCode, msg = test_results[0], test_results[1]
                resultstr = returnCodes[
                    returnCode] if returnCode in returnCodes else f"UNRECOGNIZED RETURN CODE {returnCode}"
                if returnCode != 0:
                    if first:
                        first = False
                        of.write(header)
                    msg = [f"{indent}{l}\n" for l in msg.splitlines()]
                    if msg is None or len(msg) == 0:  # prevent script failures
                        msg = " EMPTY RESPONSE"
                    firstmsg = msg[0][len(indent) - 1:]
                    rest = msg[1:]
                    m = f"{resultstr:>9}:{serverstr}" + firstmsg + "".join(rest)
                    of.write(m)


# for testing... intended to be used as a module
if __name__ == "__main__":
    # parse arguments
    parser = argparse.ArgumentParser(description='Process wekachecker json output into text file')
    parser.add_argument('json_input_file', nargs='?', default='test_results.json', type=str,
                        help='json file that was created by wekachecker (default: "test_results.json")')
    parser.add_argument('-o', dest='outfile', default='test_results.txt', type=str,
                        help='output file name (default: "test_results.txt"), "-" for stdout')

    args = parser.parse_args()
    process_json(args.json_input_file, args.outfile)
