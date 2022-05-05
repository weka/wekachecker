#
# wekassh - a simpler interface to paramiko for doing ssh to other servers
#
import getpass
import os
from logging import getLogger

import paramiko
from scp import SCPClient

from sthreads import threaded, default_threader

log = getLogger(__name__)


class AuthenticationException(Exception):
    pass

    def __str__(self):
        return "Authentication Failed"


class CommandOutput(object):
    def __init__(self, status, stdout, stderr, exception):
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.exception = exception


class RemoteServer(paramiko.SSHClient):
    def __init__(self, hostname):
        super().__init__()
        self._sshconfig = paramiko.SSHConfig()
        self._config_file = True
        self.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        self.load_system_host_keys()

        # handle missing config file
        try:
            fp = open(os.path.expanduser('~/.ssh/config'))
        except IOError:
            self.config_file = False
        else:
            try:
                self._sshconfig.parse(fp)
            except Exception as exc:  # malformed config file?
                log.critical(exc)
                raise

        self._hostname = hostname
        self.exc = None
        self.hostconfig = self._sshconfig.lookup(self._hostname)
        if "user" in self.hostconfig:
            self.user = self.hostconfig["user"]
        else:
            self.user = getpass.getuser()
        self.password = ""  # was None, but on linux it produces an error

        if "identityfile" in self.hostconfig:
            self.key_filename = self.hostconfig["identityfile"][0]  # only take the first match, like OpenSSH
        else:
            self.key_filename = None

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
        success = False
        while not success:
            self.exc = None
            self.kwargs = dict()

            if self.user is not None:
                self.kwargs["username"] = self.user
            if self.password is not None:
                self.kwargs["password"] = self.password

            # don't give key_filename if they've provided a password
            if self.key_filename is not None and "password" not in self.kwargs:
                self.kwargs["key_filename"] = self.key_filename
            else:
                self.kwargs["key_filename"] = None
                # self.kwargs["look_for_keys"] = True # actually the default...

            try:
                super().connect(self._hostname, **self.kwargs)
                success = True
            except paramiko.ssh_exception.AuthenticationException as exc:
                log.critical(f"Authentication error opening ssh session to {self._hostname}: {exc}")
                self.exc = AuthenticationException()
            except Exception as exc:
                log.critical(f"Exception opening ssh session to {self._hostname}: {exc}")
                self.exc = exc
            # ok, it's a gross hack, but we need to know if we're interactive or not
            # ___interactive is assumed True, parallel() sets it to False
            if not success:
                if getattr(self, "___interactive", True):
                    self.ask_for_credentials()
                else:
                    return  # bail out if not interactive and error

    def close(self):
        self.end_unending()  # kills the fio --server process
        super().close()

    def scp(self, source, dest):
        log.info(f"copying {source} to {self._hostname}")
        with SCPClient(self.get_transport()) as scp:
            scp.put(source, recursive=True, remote_path=dest)

    def run(self, cmd):
        exc = None
        try:
            stdin, stdout, stderr = self.exec_command(cmd, get_pty=True)
            status = stdout.channel.recv_exit_status()
            stdout.flush()
            response = stdout.read().decode("utf-8")
            error = stderr.read().decode("utf-8")
            self.last_output = {'status': status, 'response': response, 'error': error, "exc": None}
            if status != 0:
                log.debug(f"run: Bad return code from {cmd[:100]}: {status}.  Output is:")
                log.debug(f"stdout is {response[:4000]}")
                log.debug(f"stderr is {error[:4000]}")
            else:
                log.debug(f"run: 'status {status}, stdout {len(response)} bytes, stderr {len(error)} bytes")
        except Exception as exc:
            log.debug(f"run (Exception): '{cmd[:100]}', status {status}, stdout {len(response)} bytes, " +
                      f"stderr {len(error)} bytes, exception='{exc}'")
            log.debug(f"stdout is {response[:100]}")
            log.debug(f"stderr is {error[:100]}")
        self.output = CommandOutput(status, response, error, exc)
        return self.output

    def _linux_to_dict(self, separator):
        output = dict()
        if self.last_output['status'] != 0:
            log.debug(f"last output = {self.last_output}")
            raise Exception
        lines = self.last_output['response'].split('\n')
        for line in lines:
            if len(line) != 0:
                line_split = line.split(separator)
                if len(line_split) == 2:
                    output[line_split[0].strip()] = line_split[1].strip()
        return output

    def _count_cpus(self):
        """ count up the cpus; 0,1-4,7,etc """
        num_cores = 0
        cpulist = self.last_output['response'].strip(' \n').split(',')
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
            log.debug(f"{self.last_output}")
            if len(self.last_output['response']) == 0:
                log.debug(f"{self._hostname} does not have a weka filesystem mounted.")
                self.weka_mounted = False
            else:
                self.weka_mounted = True

    def file_exists(self, path):
        """ see if a file exists on another server """
        log.debug(f"checking for presence of file {path} on server {self._hostname}")
        self.run(f"if [ -f '{path}' ]; then echo 'True'; else echo 'False'; fi")
        strippedstr = self.last_output['response'].strip(' \n')
        log.debug(f"server responded with {strippedstr}")
        if strippedstr == "True":
            return True
        else:
            return False

    def last_response(self):
        return self.last_output['response'].strip(' \n')

    def __str__(self):
        return self._hostname

    def run_unending(self, command):
        """ run a command that never ends - needs to be terminated by ^c or something """
        transport = self.get_transport()
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
