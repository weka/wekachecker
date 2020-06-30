#!/usr/bin/env python

#from __future__ import absolute_import
import json
import argparse
import glob
#from plumbum import SshMachine, colors
import sys
import logging

import os
from contextlib import contextmanager


"""A Python context to move in and out of directories"""
@contextmanager
def pushd(new_dir):
    previous_dir = os.getcwd()
    os.chdir(new_dir)
    try:
        yield
    finally:
        os.chdir(previous_dir)

# print something without a newline
def announce( text ):
    sys.stdout.flush()
    sys.stdout.write(text)
    #sys.stdout.flush()

# pass server name/ip, ssh session, and list of scripts
def run_scripts( server, s, scripts ):
    scriptresults = {}
    num_warn=0
    num_fail=0
    num_pass=0
    # execute each script
    for scriptname in scripts:
        f = open( scriptname )  # open each of the scripts
        if f.mode == "r":
            script = f.read()  # suck the contents of the script file into "script"
        else:
            script=""   # open failed
            print "Unable to open " + scriptname
            continue

        if args.verbose_flag:
            print "Executing script " + scriptname + " on server " + server + ":"

        desc_start = script.find( "DESCRIPTION" )
        if desc_start != -1:
            desc_begin = script.find( '"', desc_start ) + 1
            desc_end = script.find( '"', desc_begin )
            desc = "(" + server + ") " + script[desc_begin:desc_end] 
            announce( desc.ljust(70) )

        # execute script on target server
        retcode, stdout_txt, stderr_txt = s.run( "( eval set -- " + arguments + "\n" + preamble + script + ")", retcode=None )

        scriptresults[scriptname]=[retcode,stdout_txt]     # save our results

        if retcode == 0:                # all ok
            print "\t[", colors.green | "PASS", "]" 
            num_pass += 1
        elif retcode == 255:            # HARD fail, cannot continue
            print "\t[", colors.red | "HARDFAIL", "]" 
        elif retcode == 254:            # warning
            print "\t[", colors.yellow | "WARN", "]" 
            num_warn += 1
        else:                           # minor fail
            print "\t[", colors.red | "FAIL", "]" 
            num_fail += 1
            

        if args.verbose_flag or retcode != 0:
            print "script returned:"
            print stdout_txt
            print stderr_txt
            print "=================================================="

        if retcode == 255:
            print "HARD FAIL - terminating tests.  Please resolve the issue and re-run."
            sys.exit( 1 )

    return num_pass,num_warn,num_fail,scriptresults

# parse arguments
progname=sys.argv[0]
parser = argparse.ArgumentParser(description='Execute server cert scripts on servers')
parser.add_argument('servers', metavar='servername', type=str, nargs='+',
                    help='Server Dataplane IPs to execute on')
parser.add_argument("-d", "--scriptdir", dest='scriptdir', default="etc/cluster.d", help="Directory of files to execute, typically ./etc/cluster.d")

# these next args are passed to the script and parsed in etc/preamble - this is more for syntax checking
parser.add_argument("-v", "--verbose", dest='verbose_flag', action='store_true', help="enable verbose mode")
parser.add_argument("-j", "--json", dest='json_flag', action='store_true', help="enable json output mode")
parser.add_argument("-f", "--fix", dest='fix_flag', action='store_true', help="don't just report, but fix any errors if possible")

args = parser.parse_args()

with pushd( os.path.dirname( progname ) ):
    # use our own version of plumbum - Ubuntu is broken. (one line change from orig plumbum... /bin/sh changed to /bin/bash
    sys.path.insert( 1, os.getcwd() + "/plumbum-1.6.8" )
    from plumbum import SshMachine, colors

    results={}

    #
    #  - vince - for cluster cert, execute the server cert scripts with json output, capture and import the json.
    #	Then check return codes, and import the json from the ones with json output (network config).
    #	Should this be done threaded, so they can be parallel?
    #


    # get the list of scripts in ./etc/server.d or ./etc/cluster.d, depending on the arguments - hard code for cluster certification?
    cluster_scripts = [f for f in glob.glob( "./etc/cluster.d/[0-9]*")]
    server0_scripts = [f for f in glob.glob( "./etc/server0.d/[0-9]*")]
    server1_scripts = [f for f in glob.glob( "./etc/server1.d/[0-9]*")]
    server2_scripts = [f for f in glob.glob( "./etc/server2.d/[0-9]*")]
    cluster_scripts.sort()
    server0_scripts.sort()
    server1_scripts.sort()
    server2_scripts.sort()

    tests = {}
    tests["./etc/server0.d"] = server0_scripts
    tests["./etc/server1.d"] = server1_scripts
    tests["./etc/server2.d"] = server2_scripts

    # get the preamble file - commands and settings for all scripts
    #preamblefile = open( args.scriptdir + "/../../etc/preamble" )
    preamblefile = open( "./etc/preamble" )
    if preamblefile.mode == "r":
        preamble = preamblefile.read() # suck in the contents of the preamble file
    else:
        preamble="" # open failed

    # save the server names/ips to pass to the subscripts
    arguments=""

    if args.verbose_flag:
        arguments = arguments + "-v "

    if args.json_flag:
        arguments = arguments + "-j "

    if args.fix_flag:
        arguments = arguments + "-f "

    for server in args.servers:
        arguments += server + ' '

    # debug - remove later, vcf
    #print arguments	

    cluster_results={}
    num_passed=0
    num_failed=0
    num_warned=0

    # do the cluster scripts first, but just on this one host - it's basic connectivity stuff
    rem = SshMachine( "localhost" )  # open an ssh session

    #logger = logging.getLogger("plumbum.shell")
    #myhandler = logging.StreamHandler( sys.stderr )
    #logger.addHandler( myhandler )
    #logger.setLevel(logging.DEBUG)

    #logger = logging.getLogger("plumbum.local")
    #myhandler = logging.StreamHandler( sys.stderr )
    #logger.addHandler( myhandler )
    #logger.setLevel(logging.DEBUG)

    #logger = logging.getLogger("plumbum.paramiko")
    #myhandler = logging.StreamHandler( sys.stderr )
    #logger.addHandler( myhandler )
    #logger.setLevel(logging.DEBUG)

    s = rem.session()
    passed,warned,failed,results = run_scripts( "localhost", s, cluster_scripts )
    num_passed += passed
    num_warned += warned
    num_failed += failed
    cluster_results["cluster"] = results
    rem.close()

    directory_results={}

    # execute on each server
    for directory,scripts in sorted( tests.items() ):
        print "Entering Directory " + directory
        for server in args.servers:
            results={}
            rem = SshMachine( server )  # open an ssh session
            s = rem.session()

            passed,warned,failed,results = run_scripts( server, s, scripts )
            num_passed += passed
            num_warned += warned
            num_failed += failed
            if args.verbose_flag:
                print "saving results for server " + server
            directory_results[server] = results

            # close the ssh session to this server so we're ready for the next
            rem.close()

        # save results of this dir
        cluster_results[directory] = directory_results
        directory_results = {}

    #print results
    if args.json_flag:
        print json.dumps(results, indent=2, sort_keys=True)

    print
    print "RESULTS: " + str( num_passed ) + " Tests Passed, " + str( num_failed ) + " Failed, " + str( num_warned ) + " Warnings" 
    #print json.dumps(cluster_results, indent=2, sort_keys=True)

    fp = open( "test_results.json", "w+" )
    fp.write( json.dumps(cluster_results, indent=2, sort_keys=True) )
    fp.write( "\n" )
    fp.close()


