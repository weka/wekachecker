#!/usr/bin/env python3

import argparse
import glob
import json
import logging
import os
import sys
import report
import subprocess
from contextlib import contextmanager
from colorama import Fore
from wekapyutils.wekassh import RemoteServer, parallel, pdsh
from wekapyutils.wekalogging import configure_logging, register_module, DEFAULT

#from wekalogging import configure_logging
#from wekassh import RemoteServer, parallel, pdsh

# get root logger
log = logging.getLogger()


@contextmanager
def pushd(new_dir):
    """A Python context to move in and out of directories"""
    previous_dir = os.getcwd()
    os.chdir(new_dir)
    try:
        yield
    finally:
        os.chdir(previous_dir)


# print( something without a newline )
def announce(text):
    sys.stdout.flush()
    sys.stdout.write(text)
    sys.stdout.flush()


# finds a string variable in the script, such as DESCRIPTION="this is a description"
def find_value(script, name):
    desc_start = script.find(name)
    if desc_start != -1:
        desc_begin = script.find('"', desc_start) + 1
        desc_end = script.find('"', desc_begin)
        desc = script[desc_begin:desc_end]
        return (desc)
    else:
        return ("ERROR: Script lacks variable declaration for " + name)


# pass server name/ip, ssh session, and list of scripts
def run_scripts(workers, scripts, args, preamble):
    PASS = f" [{Fore.GREEN}PASS{Fore.RESET}]"
    WARN = f" [{Fore.YELLOW}WARN{Fore.RESET}]"
    FAIL = f" [{Fore.RED}FAIL{Fore.RESET}]"
    HARDFAIL = f" [{Fore.RED}HARDFAIL{Fore.RESET}]"
    num_warn = 0
    num_fail = 0
    num_pass = 0

    # execute each script
    for scriptname in scripts:
        f = open(scriptname)  # open each of the scripts
        if f.mode == "r":
            script = f.read()  # suck the contents of the script file into "script"
        else:
            script = ""  # open failed
            announce("\nUnable to open " + scriptname + "\n")
            continue

        # saw that script we're going to run:
        description = find_value(script, "DESCRIPTION")
        resultkey = f"{os.path.basename(scriptname)}:{description}"
        announce(description.ljust(60))

        script_type = find_value(script, "SCRIPT_TYPE")  # should be "single", "parallel", or "sequential"

        command = "( eval set -- " + args + "\n" + preamble + script + ")"

        if script_type == "single":

            server = workers[0]
            # run on a single server - doesn't matter which
            server.run(command)
            if not resultkey in results:
                results[resultkey] = {}
            results[resultkey][str(server)] = [server.output.status,
                                                server.output.stdout]
            max_retcode = server.output.status

        elif script_type == "sequential":
            max_retcode = 0
            for server in workers:
                # run on all servers, but one at a time (sequentially)
                server.run(command)
                if not resultkey in results:
                    results[resultkey] = {}
                results[resultkey][str(server)] = [server.output.status,
                                                    server.output.stdout]

                # note if any failed/warned.
                if server.output.status > max_retcode:
                    max_retcode = server.output.status

        elif script_type == "parallel":
            # run on all servers in parallel
            max_retcode = 0

            # create and start the threads
            pdsh(workers, command)
            for server in workers:
                if not resultkey in results:
                    results[resultkey] = {}
                results[resultkey][str(server)] = [server.output.status,
                                                    server.output.stdout]
                # note if any failed/warned.
                if server.output.status > max_retcode:
                    max_retcode = server.output.status
        else:
            announce("\nERROR: Script failure: SCRIPT_TYPE in script " + scriptname + " not set.\n")
            print("HARD FAIL - terminating tests.  Please resolve the issue and re-run.")
            sys.exit(1)

        # end of the if statment - check the return codes
        if max_retcode == 0:  # all ok
            print(PASS)
            num_pass += 1
        elif max_retcode == 255:  # HARD fail, cannot continue
            print(HARDFAIL)
        elif max_retcode == 254:  # warning
            print(WARN)
            num_warn += 1
        else:  # minor fail
            print(FAIL)
            num_fail += 1

        if max_retcode == 255:
            print("HARD FAIL - terminating tests.  Please resolve the issue and re-run.")
            # return early
            return num_pass, num_warn, num_fail, results

    return num_pass, num_warn, num_fail, results


#
#   main
#

# parse arguments
progname = sys.argv[0]
parser = argparse.ArgumentParser(description='Check if servers are ready to run Weka')
parser.add_argument('servers', metavar='dataplane_ips', type=str, nargs='+',
                    help='Server DATAPLANE IPs to execute on')
parser.add_argument("-c", "--clusterscripts", dest='clusterscripts', action='store_true',
                    help="Execute cluster-wide scripts")
parser.add_argument("-s", "--serverscripts", dest='serverscripts', action='store_true',
                    help="Execute server-specific scripts")
parser.add_argument("-w", "--workload", dest='workload', default="default",
                    help="workload definition directory (a subdir of scripts.d)")

# these next args are passed to the script and parsed in etc/preamble - this is more for syntax checking
parser.add_argument("-v", "--verbose", dest='verbosity', action='store_true', help="enable verbose mode")
parser.add_argument("-j", "--json", dest='json_flag', action='store_true', help="enable json output mode")
parser.add_argument("-f", "--fix", dest='fix_flag', action='store_true',
                    help="don't just report, but fix any errors if possible")

args = parser.parse_args()
# local modules
register_module("wekachecker", DEFAULT)
#register_module("wekassh", DEFAULT)
register_module("paramiko", logging.ERROR)
configure_logging(log, args.verbosity)

# load our ssh configuration
remote_servers = list()

#try:
#    wd = sys._MEIPASS  # for PyInstaller - this is the temp dir where we are unpacked
#except AttributeError:
#    ab = os.path.abspath(progname)
#    wd = os.path.dirname(ab)
ab = os.path.abspath(progname)
wd = os.path.dirname(ab)

with pushd(wd):  # change to this dir so we can find "./scripts.d"
    # make sure passwordless ssh works to all the servers because nothing will work if not set up
    announce("Opening ssh sessions to all servers\n")
    parallel_threads = {}
    for host in args.servers:
        remote_servers.append(RemoteServer(host))

    # print(f"opening ssh sessions to all servers")

    # open ssh sessions to the servers - errors are in workers[<servername>].exc
    # loop through all rather than parallel because 
    # some may be passwordless, others not.   If any are not, assumes the rest
    # will use the same user/pw
    user, pw = None, None
    for server in remote_servers:
        if pw != None:
            server.user, server.password = user, pw
        ot = subprocess.PIPE
        p = subprocess.Popen(["ping", "-c1", server._hostname], stdout=ot, stderr=ot)
        pstdout, pstderr = p.communicate()
        if p.returncode > 0: 
            announce(f"Unable to ping {server._hostname}; skipping connect attempt\n")
            server.exc = Exception("Ping failed.")
            continue
        server.connect()
        if len(server.password) > 0 and server.password != pw:
            user, pw = server.user, server.password

    errors = False
    for server in remote_servers:
        if server.exc is not None:
            # we had an error connecting
            print(f"Error connecting to {server}: {server.exc}; aborting")
            errors = True
        #else:
        #    server.run("sudo /bin/bash")
    if errors:
        sys.exit(1)

    # ok, we're good... let's go
    results = {}

    # get the list of scripts in ./etc/scripts.d
    if not args.clusterscripts and not args.serverscripts:
        # unspecicified by user so execute all scripts
        scripts = [f for f in glob.glob(f"./scripts.d/{args.workload}/[0-9]*")]
    else:
        scripts = []
        if args.clusterscripts:
            scripts += [f for f in glob.glob(f"./scripts.d/{args.workload}/0*")]
        if args.serverscripts:
            scripts += [f for f in glob.glob(f"./scripts.d/{args.workload}/[1-2]*")]

    # sort them so they execute in the correct order
    scripts.sort()

    # get the preamble file - commands and settings for all scripts
    preamblefile = open(f"scripts.d/default/preamble")
    if preamblefile.mode == "r":
        preamble = preamblefile.read()  # suck in the contents of the preamble file
    else:
        preamble = ""  # open failed

    # save the server names/ips to pass to the subscripts
    arguments = ""

    # if args.verbose_flag:
    #    arguments = arguments + "-v "

    if args.json_flag:
        arguments = arguments + "-j "

    if args.fix_flag:
        arguments = arguments + "-f "

    for server in args.servers:
        arguments += server + ' '

    cluster_results = {}

    num_passed, num_warned, num_failed, results = run_scripts(remote_servers, scripts, arguments, preamble)

    if args.json_flag:
        print(json.dumps(results, indent=2, sort_keys=True))

    print()
    print("RESULTS: " + str(num_passed) + " Tests Passed, " + str(num_failed) + " Failed, " + str(
        num_warned) + " Warnings")
    # print( json.dumps(cluster_results, indent=2, sort_keys=True) )

# dump out of the pushd() so we can save the test_results.json in the current dir
fp = open("test_results.json", "w+")  # Vin - add date/time to file name
fp.write(json.dumps(results, indent=4, sort_keys=True))
fp.write("\n")
fp.close()

report.process_json("test_results.json", "test_results.txt", print_stdout=False)

