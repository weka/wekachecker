#!/usr/bin/env python3

import json
import argparse

def zfillIP4(host):   # returns zero filled IP4 if host is valid IP4.  otherwise returns host
    result = [n.zfill(3) for n in host.split(".") if n.isdigit() and 0<=int(n)<=255]
    if len(result) == 4:
        return ".".join(result), True
    else:
        return host, False

def process_json(infile, outfile, print_stdout=True):
    returnCodes = {0: "PASS", 1: "*FAIL", 127: "CMD TO RUN WAS NOT IN PATH", 254: "WARN", 255: "*HARDFAIL"}
    indent = ' ' * 6
    with open( infile ) as fp:
        results = json.load( fp )
    with open (outfile, 'w') as of:
        for scriptname_description, server_dict in results.items():
            scriptname, description = scriptname_description.split(":")
            first = True
            header = f"\n{scriptname}:\n  {description}\n"
            for server, test_results in server_dict.items():
                # server, _ = zfillIP4(server)
                serverstr = f" {server + ': ':<17}"
                returnCode, msg = test_results[0], test_results[1]
                resultstr = returnCodes[returnCode]
                if returnCode != 0:
                    if first:
                        first = False
                        if print_stdout:
                            print(header)
                        of.write(header)
                    msg = [f"{indent}{l}\n" for l in msg.splitlines()]
                    if msg and msg[0]:
                        pass
                    else:
                        msg = " EMPTY RESPONSE"
                    firstmsg = msg[0][len(indent)-1:]
                    rest = msg[1:]
                    m = f"{resultstr:>9}:{serverstr}" + firstmsg + "".join(rest)
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
