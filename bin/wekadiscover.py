#!/usr/bin/env python
import socket, sys, sets, signal

class TimeoutException(Exception):
    pass

def timeout_handler(signum, frame):
    raise TimeoutException

signal.signal(signal.SIGALRM, timeout_handler)

incoming_packets = []

def unique_set(seq):
   # Not order preserving    
   set = sets.Set(seq)
   return list(set)

def display_results():
    print unique_set( incoming_packets )


def gather_packets():
    client = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP) # UDP
    client.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    client.bind(('', 14098))
    while True:
        data, addr = client.recvfrom(1024)
        #host, port = socket.getnameinfo( addr, socket.NI_NUMERICHOST )
        host, port = socket.getnameinfo( addr, 0 )
        print("received message from " + str( host ) + ": %s"%data)
        if data == "weka.io matrix v3.3.3":
	    print "\tfound v3.3.3"
            incoming_packets.append( host )

signal.alarm(5)    
try:
    gather_packets()
except TimeoutException:
    print "timeout."

display_results()
