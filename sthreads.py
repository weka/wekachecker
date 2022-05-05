#
# sthreads module - implement simultaneous thread management
#

# author: Vince Fleming, vince@weka.io
import functools
import threading
import time
from logging import getLogger

log = getLogger(__name__)


# ---------------- start of threader definition ------------
# manage threads - start only num_simultaneous threads at a time
#
# You should add all the threads, then start all via run().
# ***Execution order is random***
class simul_threads():

    def __init__(self, num_simultaneous):
        self.num_simultaneous = num_simultaneous  # max number of threads to run at any given time
        self.ids = 0  # thread id... a counter that increases over time
        self.staged = {}  # threads that need to be run - dict of {threadid:thread_object}
        self.running = {}  # currently running threads that will need to be reaped - dict (same as staged)
        self.dead = {}
        log.debug(f"object created; num_simultaneous={self.num_simultaneous}")

    # create a thread and put it in the list of threads
    def new(self, function, *args, **kwargs):
        log.debug(f"creating new thread, func={function}")
        self.ids += 1
        self.staged[self.ids] = threading.Thread(target=function, args=args, kwargs=kwargs)
        self.staged[self.ids].daemon = True  # these will die when the main thread dies

    def status(self):
        print("Current status of threads:")
        for threadid, thread in self.running.items():
            print("Threadid: " + str(threadid) + " is " + ("alive" if thread.is_alive() else "dead"))
        for threadid, thread in self.staged.items():
            print("Threadid: " + str(threadid) + " is staged")
        return len(self.staged) + len(self.running)

    # look for threads that need reaping, start next thread
    def reaper(self):
        # log.debug(f"reaping threads")
        for threadid, thread in self.running.items():
            if not thread.is_alive():
                thread.join()  # reap it (wait for it)
                self.dead[threadid] = thread  # note that it's dead/done

        # remove them from the running list
        for threadid, thread in self.dead.items():
            self.running.pop(threadid)  # delete it from the running list

        self.dead = {}  # reset dead list, as we're done with those threads

    # start threads, but only a few at a time
    def starter(self):
        # only allow num_simultaneous threads to run at one time
        log.debug(
            f"starting threads; num_simultaneous={self.num_simultaneous}, running={len(self.running)}, staged={len(self.staged)}")
        while len(self.running) < self.num_simultaneous and len(self.staged) > 0:
            threadid, thread = self.staged.popitem()  # take one off the staged list
            thread.start()  # start it
            self.running[threadid] = thread  # put it on the running list

    def num_active(self):
        return len(self.running)

    def num_staged(self):
        return len(self.staged)

    # run all threads, wait for all to complete
    def run(self):
        log.debug(f"running threads")
        log.debug(
            f"starting threads; num_simultaneous={self.num_simultaneous}, running={len(self.running)}, staged={len(self.staged)}")
        while len(self.staged) + len(self.running) > 0:
            self.reaper()  # reap any dead threads
            self.starter()  # kick off threads
            time.sleep(0.1)  # limit CPU use


# ---------------- end of threader definition ------------

default_threader = simul_threads(100)


def threaded(_func=None, *, threader=default_threader):
    """ decorator function for threading """

    def decorator_threaded(func):
        @functools.wraps(func)
        def wrapper_threaded(*args, **kwargs):
            threader.new(func, *args, **kwargs)

        return wrapper_threaded

    if _func is None:
        return decorator_threaded
    else:
        return decorator_threaded(_func)
