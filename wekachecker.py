#!/usr/bin/env python3

import argparse
import getpass
import glob
# from __future__ import absolute_import
import json
import os
import sys
from contextlib import contextmanager

from colorama import Fore

from wekassh import SshConfig, WorkerServer, parallel, AuthenticationException, pdsh

"""A Python context to move in and out of directories"""


@contextmanager
def pushd(new_dir):
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
        announce(find_value(script, "DESCRIPTION").ljust(70))

        script_type = find_value(script, "SCRIPT_TYPE")  # should be "single", "parallel", or "sequential"

        command = "( eval set -- " + args + "\n" + preamble + script + ")"

        if script_type == "single":

            server = workers[0]
            # run on a single server - doesn't matter which
            server.run(command)
            if not scriptname in results:
                results[scriptname] = {}
            results[scriptname][str(server)] = [server.last_output["status"],
                                                server.last_output["response"]]
            max_retcode = server.last_output["status"]

        elif script_type == "sequential":
            max_retcode = 0
            for server in workers:
                # run on all servers, but one at a time (sequentially)
                server.run(command)
                if not scriptname in results:
                    results[scriptname] = {}
                results[scriptname][str(server)] = [server.last_output["status"],
                                                    server.last_output["response"]]

                # note if any failed/warned.
                if server.last_output["status"] > max_retcode:
                    max_retcode = server.last_output["status"]

        elif script_type == "parallel":
            # run on all servers in parallel
            # global thread_results
            max_retcode = 0

            # create and start the threads
            pdsh(workers, command)
            for server in workers:
                if not scriptname in results:
                    results[scriptname] = {}
                results[scriptname][str(server)] = [server.last_output["status"],
                                                    server.last_output["response"]]
                # note if any failed/warned.
                if server.last_output["status"] > max_retcode:
                    max_retcode = server.last_output["status"]
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


def ask_for_credentials(user):
    actual_user = getpass.getuser()
    print(f"Username({actual_user}): ", end='')
    user = input()
    if len(user) == 0:
        user = actual_user

    password = getpass.getpass()
    print()
    return (user, password)


def get_creds(workers):  # prompt user for userid and password, set all hosts to same
    sample_host = workers[0]  # pick any one
    user, password = ask_for_credentials(sample_host.user)
    for worker in workers:
        worker.user = user
        worker.password = password


#
#   main
#

# parse arguments
progname = sys.argv[0]
parser = argparse.ArgumentParser(description='Execute server cert scripts on servers')
parser.add_argument('servers', metavar='servername', type=str, nargs='+',
                    help='Server Dataplane IPs to execute on')
# parser.add_argument("-d", "--scriptdir", dest='scriptdir', default="etc/cluster.d", help="Directory of files to execute, typically ./etc/cluster.d")
parser.add_argument("-c", "--clusterscripts", dest='clusterscripts', action='store_true',
                    help="Execute cluster-wide scripts")
parser.add_argument("-s", "--serverscripts", dest='serverscripts', action='store_true',
                    help="Execute server-specific scripts")
parser.add_argument("-p", "--perfscripts", dest='perfscripts', action='store_true', help="Execute performance scripts")

# these next args are passed to the script and parsed in etc/preamble - this is more for syntax checking
# parser.add_argument("-v", "--verbose", dest='verbose_flag', action='store_true', help="enable verbose mode")
parser.add_argument("-j", "--json", dest='json_flag', action='store_true', help="enable json output mode")
parser.add_argument("-f", "--fix", dest='fix_flag', action='store_true',
                    help="don't just report, but fix any errors if possible")

args = parser.parse_args()

# load our ssh configuration
sshconfig = SshConfig()
workers = list()

with pushd(os.path.dirname(progname)):
    # make sure passwordless ssh works to all the servers because nothing will work if not set up
    announce("Opening ssh sessions to all servers\n")
    parallel_threads = {}
    for host in args.servers:
        workers.append(WorkerServer(host, sshconfig))

    success = False
    while not success:
        error_count = 0
        auth_errors = 0
        # open ssh sessions to the servers - errors are in workers[<servername>].exc
        parallel(workers, WorkerServer.open)

        for host in workers:
            if host.exc != None:
                error_count += 1
                if type(host.exc) == AuthenticationException:
                    print("correctly detected Auth Exception")
                    auth_errors += 1
                else:
                    print(f"host {host} returned error: {host.exc}")
                    error_count += 1
        if auth_errors > 0:
            get_creds(workers)  # prompt user for userid and password, set all hosts to same
        if error_count == 0:
            success = True

    announce("\n")

    # ok, we're good... let's go
    results = {}

    # get the list of scripts in ./etc/server.d or ./etc/cluster.d, depending on the arguments - hard code for cluster certification?
    if not args.clusterscripts and not args.serverscripts and not args.perfscripts:
        # unspecicified by user so execute all scripts
        scripts = [f for f in glob.glob("./scripts.d/[0-9]*")]
    else:
        scripts = []
        if args.clusterscripts:
            scripts += [f for f in glob.glob("./scripts.d/0*")]
        if args.serverscripts:
            scripts += [f for f in glob.glob("./scripts.d/[1-2]*")]
        if args.perfscripts:
            scripts += [f for f in glob.glob("./scripts.d/5*")]

    # sort them so they execute in the correct order
    scripts.sort()

    # get the preamble file - commands and settings for all scripts
    preamblefile = open("./scripts.d/preamble")
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

    num_passed, num_warned, num_failed, results = run_scripts(workers, scripts, arguments, preamble)

    if args.json_flag:
        print(json.dumps(results, indent=2, sort_keys=True))

    print()
    print("RESULTS: " + str(num_passed) + " Tests Passed, " + str(num_failed) + " Failed, " + str(
        num_warned) + " Warnings")
    # print( json.dumps(cluster_results, indent=2, sort_keys=True) )

    fp = open("test_results.json", "w+")  # Vin - add date/time to file name
    fp.write(json.dumps(results, indent=4, sort_keys=True))
    fp.write("\n")
    fp.close()
