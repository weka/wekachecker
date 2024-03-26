#
# wekassh - a simpler interface to paramiko for doing ssh to other servers
#
import getpass
import os
from logging import getLogger

import fabric
#import paramiko
#from scp import SCPClient

from wekapyutils.sthreads import threaded, default_threader

log = getLogger(__name__)


class AuthenticationException(Exception):
    pass

    def __str__(self):
        return "Authentication Failed"


class CommandOutput(object):
    def __init__(self, status, stdout, stderr, exception=None):
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.exception = exception

    def __str__(self):
        return f"status={self.status}, stdout={self.stdout}, stderr={self.stderr}, exception={self.exception}"


class RemoteServer():
    def __init__(self, hostname):
        self.output = None
        #self.connection = fabric.Connection(hostname)
        self.connection = None
        self._hostname = hostname
        self.exc = None
        self.user = ""
        self.password = ""

    def ask_for_credentials(self):
        print(f"Enter credentials for server {self._hostname}:")
        print(f"Username({self.user}): ", end='')
        user = input()
        if len(user) != 0:
            self.user = user
        self.password = getpass.getpass()
        print()
        # return (user, password)

    def connect(self):
        try:
            self.connection = fabric.Connection(self._hostname, forward_agent=True)
            result = self.connection.open()
        except Exception as exc:
            log.error(f"Error connecting to {self._hostname}: {exc}")
            self.user = self.connection.user
            self.ask_for_credentials()
            connect_kwargs = {"password": self.password, "key_filename": []}
            del self.connection
            self.connection = fabric.Connection(self._hostname, user=self.user, connect_kwargs=connect_kwargs)
            result = self.connection.open()
        return self.connection

    def close(self):
        self.end_unending()  # kills the fio --server process
        self.connection.close()
        #super().close()
        
    def get_transport(self):
        return self.connection.transport

    def scp(self, source, dest):
        log.info(f"copying {source} to {self._hostname}")
        self.connection.put(source, dest)

    def run(self, cmd):
        """

        :param cmd:
        :type cmd:
        :return:returns a CommandOutput object with the results of the command
                         and also stores it in self.output
        :rtype:
        """
        try:
            result = self.connection.run(cmd, hide=True)
            #self.output = CommandOutput(result.return_code, result.stdout, result.stderr, exc)
        except Exception as exc:
            log.debug(f"run (Exception): '{cmd[:100]}', exception='{exc}'")
            result = exc.result
            self.output = CommandOutput(result.return_code, result.stdout, result.stderr, exc)
        else:
            self.output = CommandOutput(result.return_code, result.stdout, result.stderr)
        return self.output

    def _linux_to_dict(self, separator):
        output = dict()
        if self.output['status'] != 0:
            log.debug(f"last output = {self.output}")
            raise Exception
        lines = self.output['response'].split('\n')
        for line in lines:
            if len(line) != 0:
                line_split = line.split(separator)
                if len(line_split) == 2:
                    output[line_split[0].strip()] = line_split[1].strip()
        return output

    def _count_cpus(self):
        """ count up the cpus; 0,1-4,7,etc """
        num_cores = 0
        cpulist = self.output.stdout.strip(' \n').split(',')
        for item in cpulist:
            if '-' in item:
                parts = item.split('-')
                num_cores += int(parts[1]) - int(parts[0]) + 1
            else:
                num_cores += 1
        return num_cores

    def gather_facts(self, weka):
        """ build a dict from the output of lscpu """
        self.cpu_info = dict()
        self.run("lscpu")

        # cpuinfo = self.last_output['response']
        self.cpu_info = self._linux_to_dict(':')

        self.run("cat /etc/os-release")
        self.os_info = self._linux_to_dict('=')

        self.run("cat /sys/fs/cgroup/cpuset/system/cpuset.cpus")
        self.usable_cpus = self._count_cpus()

        if weka:
            self.run('mount | grep wekafs')
            log.debug(f"{self.output}")
            if len(self.output['response']) == 0:
                log.debug(f"{self._hostname} does not have a weka filesystem mounted.")
                self.weka_mounted = False
            else:
                self.weka_mounted = True

    def file_exists(self, path):
        """ see if a file exists on another server """
        log.debug(f"checking for presence of file {path} on server {self._hostname}")
        self.run(f"if [ -f '{path}' ]; then echo 'True'; else echo 'False'; fi")
        strippedstr = self.output['response'].strip(' \n')
        log.debug(f"server responded with {strippedstr}")
        if strippedstr == "True":
            return True
        else:
            return False

    def last_response(self):
        return self.output

    def __str__(self):
        return self._hostname

    def run_unending(self, command):
        """ run a command that never ends - needs to be terminated by ^c or something """
        #transport = self.get_transport()
        transport = self.connection.get_transport()
        self.unending_session = transport.open_session()
        self.unending_session.setblocking(0)  # Set to non-blocking mode
        self.unending_session.get_pty()
        self.unending_session.invoke_shell()
        self.unending_session.command = command

        # Send command
        log.debug(f"starting daemon {self.unending_session.command}")
        self.unending_session.send(command + '\n')

    def end_unending(self):
        log.debug(f"terminating daemon {self.unending_session.command}")
        self.unending_session.send(chr(3))  # send a ^C
        self.unending_session.close()


@threaded
def threaded_method(instance, method, *args, **kwargs):
    """ makes ANY method of ANY class threaded """
    method(instance, *args, **kwargs)


def parallel(obj_list, method, *args, **kwargs):
    for instance in obj_list:
        instance.___interactive = False  # mark them all as parallel jobs
        threaded_method(instance, method, *args, **kwargs)
    default_threader.run()  # wait for them
    for instance in obj_list:
        instance.___interactive = True  # undo that when done


def pdsh(servers, command):
    parallel(servers, RemoteServer.run, command)


def pscp(servers, source, dest):
    log.debug(f"setting up parallel copy to {servers}")
    parallel(servers, RemoteServer.scp, source, dest)

if __name__ == '__main__':
    test1 = RemoteServer("wms")
    result = test1.connect()
    result2 = test1.run("date")
    print(result2)
    print(result2.stdout)
    test1.scp("wekassh2.py", "/tmp/wekassh2.py")

    servers = [RemoteServer("wms"), RemoteServer("buckaroo"), RemoteServer("whorfin")]
    parallel(servers, RemoteServer.run, "hostname")
    default_threader.run()
    print("done")
    for i in servers:
        print(i.last_response())
    pass