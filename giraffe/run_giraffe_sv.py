#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# run Giraffe prover and verifier as simulated Verilog

import getopt
import os
import random
import select
import sys

sys.path.insert(1, os.path.abspath(os.path.join(os.path.dirname(__file__), 'giraffetempl')))
import giraffetempl.computation as computation
import giraffetempl.prover as prover
import giraffetempl.verifier as verifier
import giraffetempl.util as tutil

sys.path.insert(1, os.path.abspath(os.path.join(os.path.dirname(__file__), 'pypws')))
import pypws

sys.path.insert(1, os.path.abspath(os.path.join(os.path.dirname(__file__), 'vpintf')))
from vpintf.clients import GiraffeCoordinator, GiraffeClient
from vpintf.defs import Defs
import vpintf.util as util

class ServerInfo(object):
    port = 27352
    host = "localhost"
    started = False
    done = False
    debug = False
    quiet = False
    sweval = False

    nCopyBits = 4
    nParBitsP = 2
    nParBitsPH = 0
    nParBitsV = 1
    nParBitsVLay = 0
    plStages = 0
    pws_file = None

    @classmethod
    def reset(cls):
        cls.started = False
        cls.done = False
        cls.outputs = None
        cls.success = None

        for c in [cls.Trusted, cls.Untrusted, cls.Native]:
            c.reset()

    outputs = None
    muxsels = None
    inputs = None
    rundir = None
    success = None

    class Trusted(object):
        add = 0
        mul = 0
        rand = 0
        addinsts = 0
        mulinsts = 0
        delay = 0

        @classmethod
        def reset(cls):
            cls.add = 0
            cls.mul = 0
            cls.rand = 0
            cls.addinsts = 0
            cls.mulinsts = 0
            cls.delay = 0

    class Untrusted(object):
        add = 0
        mul = 0
        rand = 0
        addinsts = 0
        mulinsts = 0
        delay = 0

        @classmethod
        def reset(cls):
            cls.add = 0
            cls.mul = 0
            cls.rand = 0
            cls.addinsts = 0
            cls.mulinsts = 0
            cls.delay = 0

    class Native(object):
        add = 0
        mul = 0
        rand = 0
        addinsts = 0
        mulinsts = 0
        delay = 0

        @classmethod
        def reset(cls):
            cls.add = 0
            cls.mul = 0
            cls.rand = 0
            cls.addinsts = 0
            cls.mulinsts = 0
            cls.delay = 0

def get_usage():
    filler = " " * len(sys.argv[0])
    uStr  = "Usage: %s [-c <nCopyBits>] [-P <nParBitsP>] [-S <plStages>]\n" % sys.argv[0]
    uStr += "       %s [-V <nParBitsV>] [-L <nParBitsVLay>] -p <pwsFile>\n" % filler
    uStr += "       %s [-d <runDir>] [-h] [-D] [-q]\n\n" % filler

    uStr += " -d runDir         run Icarus from runDir after generating files\n"
    uStr += "                   (else generate files in PWD, wait for user to run Icarus)\n"
    oStr = "d:"

    uStr += " -h                show this help message and quit\n"
    oStr += "h"

    uStr += " -D                enable debugging\n"
    oStr += "D"

    uStr += " -N                skip Verilog simulation of AC, only V and P\n"
    oStr += "N"

    uStr += " -q                quiet(er) execution for Verilog simulator\n\n"
    oStr += "q"

    uStr += " option            description                         default\n"
    uStr += " --                --                                  --\n"
    uStr += " -p pwsFile        PWS describing computation to run   (must be supplied)\n"
    oStr += "p:"

    uStr += " -c nCopyBits      log2(#copies) to verify in parallel (%d)\n" % ServerInfo.nCopyBits
    oStr += "c:"

    uStr += " -P nParBitsP      log2(parallelism) for P layer       (%d)\n" % ServerInfo.nParBitsP
    oStr += "P:"

    uStr += " -H nParBitsPH     log2(parallelism) for H in P layer  (%d)\n" % ServerInfo.nParBitsPH
    oStr += "H:"

    uStr += " -S plStages       #pipeline stages in shuffle tree    (%d)\n" % ServerInfo.plStages
    oStr += "S:"

    uStr += " -V nParBitsV      log2(parallelism) for V i/o         (%d)\n" % ServerInfo.nParBitsV
    oStr += "V:"

    uStr += " -L nParBitsVLay   log2(parallelism) for V layers      (%d)\n" % ServerInfo.nParBitsVLay
    oStr += "L:"

    return (oStr, uStr)

def get_params():
    (oStr, uStr) = get_usage()

    def exit_with_error(msg, exitcode=1):
        print uStr
        if msg is not None:
            print "ERROR:", msg
        sys.exit(exitcode)

    def check_and_set(propName, val):
        if val < getattr(ServerInfo, propName):
            exit_with_error("minimum value for %s is %d" % (propName, getattr(ServerInfo, propName)))
        setattr(ServerInfo, propName, val)

    try:
        (opts, args) = getopt.getopt(sys.argv[1:], oStr)
    except getopt.GetoptError as err:
        exit_with_error(str(err))

    if len(args) > 0:
        exit_with_error("extraneous arguments. Giving up.")

    for (opt, arg) in opts:
        if opt == "-h":
            exit_with_error(None, 0)
        elif opt == "-p":
            ServerInfo.pws_file = arg
        elif opt == "-c":
            check_and_set("nCopyBits", int(arg))
        elif opt == "-P":
            check_and_set("nParBitsP", int(arg))
        elif opt == "-H":
            check_and_set("nParBitsPH", int(arg))
        elif opt == "-S":
            check_and_set("plStages", int(arg))
        elif opt == "-V":
            check_and_set("nParBitsV", int(arg))
        elif opt == "-L":
            check_and_set("nParBitsVLay", int(arg))
        elif opt == "-D":
            ServerInfo.debug = True
        elif opt == "-q":
            ServerInfo.quiet = True
        elif opt == "-N":
            ServerInfo.sweval = True
        elif opt == "-d":
            ServerInfo.rundir = arg
        else:
            exit_with_error("unexpected option passed. Giving up.")

    if ServerInfo.pws_file is None:
        exit_with_error("you must supply a PWS file!")
    elif not os.path.isfile(ServerInfo.pws_file):
        exit_with_error("PWS file '%s' does not exist" % ServerInfo.pws_file)

    if ServerInfo.nCopyBits - ServerInfo.nParBitsP < 2:
        exit_with_error("nCopyBits must be at least 2 more than nParBitsP")

def rwsplit(sts, ret):
    diffs = {}
    for idx in sts:
        st = sts[idx]
        if st.sock is not None:
            val = select.POLLIN

            if st.want_write:
                val = val | select.POLLOUT

            if ret.get(idx) != val:
                ret[idx] = val
                diffs[idx] = True

        else:
            ret[idx] = 0
            diffs[idx] = False

    return diffs


def handle_server_sock(lsock, state_id_map, state_fd_map):
    ns = util.accept_socket(lsock)
    nstate = GiraffeClient(ns)

    client_id = random.getrandbits(31)
    state_id_map[client_id] = nstate
    state_fd_map[nstate.fileno()] = nstate
    nstate.client_id = client_id

    if Defs.debug:
        print "SERVER new connection, assigning id %s" % client_id


def run():
    lsock = util.listen_socket(ServerInfo.host, ServerInfo.port, 128)
    lsock_fd = lsock.fileno()

    state_fd_map = {}
    rwflags = {}
    state_id_map = {}
    npasses_out = 0
    poll_obj = select.poll()
    poll_obj.register(lsock_fd, select.POLLIN)

    if ServerInfo.rundir is not None:
        if os.fork() == 0:
            os.chdir(ServerInfo.rundir)
            os.execlp("make", "make", "-j", "frompws")

    def show_status():
        if not Defs.debug:
            return

        tstates = len(state_id_map)
        fstates = len(state_fd_map)
        rwstates = len(rwflags)
        print "SERVER status: conn_id=%d conn_fd=%d conn_flags=%d" % (tstates, fstates, rwstates)

        for f in state_fd_map:
            st = state_fd_map[f]
            print "%d: (%s) %s %d %d" % (f, st.client_id, str(st.sock), st.want_handle, st.want_write)

    while True:
        dflags = rwsplit(state_id_map, rwflags)

        for idx in dflags:
            if rwflags.get(idx, 0) != 0:
                poll_obj.register(state_id_map[idx], rwflags[idx])
            else:
                try:
                    poll_obj.unregister(state_id_map[idx])
                except:
                    pass

            if not dflags[idx]:
                if Defs.debug:
                    print "SERVER Deleting state %s" % idx
                assert len(state_id_map[idx].recv_queue) == 0
                assert state_id_map[idx].sock is None

                fno = state_id_map[idx].fileno()
                state_id_map[idx].close()
                rwflags[idx] = None
                state_id_map[idx] = None
                state_fd_map[fno] = None
                del rwflags[idx]
                del state_id_map[idx]
                del state_fd_map[fno]

        if lsock is None and lsock_fd is not None:
            poll_obj.unregister(lsock_fd)
            lsock_fd = None

        if npasses_out == 100:
            npasses_out = 0
            show_status()

        pfds = poll_obj.poll(1000)
        npasses_out += 1

        if len(pfds) == 0:
            show_status()

        # read all ready sockets for new messages
        for (fd, ev) in pfds:
            if (ev & select.POLLIN) != 0:
                if lsock is not None and fd == lsock_fd:
                    handle_server_sock(lsock, state_id_map, state_fd_map)

                else:
                    state_fd_map[fd].do_read()

        # handle messages from each connection
        for idx in state_id_map:
            state = state_id_map[idx]
            if state.client_type is None and state.want_handle:
                state.initialize()

                if Defs.debug:
                    print "SERVER got connection from id %s of type %d" % (idx, state.client_type)

            while state.want_handle:
                state.do_handle()

        # send ready messages on each connection that's writable
        for (fd, ev) in pfds:
            if (ev & select.POLLOUT) != 0:
                state_fd_map[fd].do_write()

        # if we haven't started yet, check whether we can do so now
        if (not ServerInfo.started) and GiraffeCoordinator.is_ready():
            ServerInfo.started = True
            GiraffeCoordinator.start_computation()

        if ServerInfo.done:
            if all([ (rwflags.get(idx, 0) & select.POLLOUT) == 0 for idx in rwflags ]):
                break
        elif GiraffeCoordinator.done:
            ServerInfo.done = True
            gcc = GiraffeCoordinator.Computation
            gcp = GiraffeCoordinator.Prover
            gcv = GiraffeCoordinator.Verifier
            for l in gcc.layers + gcp.layers + gcv.layers + [gcp.shim, gcv.inputs, gcv.outputs]:
                if len(l.counts) < 1:
                    ServerInfo.done = False
                elif not l.did_print:
                    l.did_print = True
                    l.enqueue(chr(Defs.VP_TYPE_QUIT))
                    (a, m, r, ac, mc, d) = l.counts[0]
                    if l.is_trusted:
                        ServerInfo.Trusted.add += a
                        ServerInfo.Trusted.mul += m
                        ServerInfo.Trusted.rand += r
                        ServerInfo.Trusted.addinsts += ac
                        ServerInfo.Trusted.mulinsts += mc
                        ServerInfo.Trusted.delay = max(ServerInfo.Trusted.delay, d)
                    else:
                        ServerInfo.Untrusted.add += a
                        ServerInfo.Untrusted.mul += m
                        ServerInfo.Untrusted.rand += r
                        ServerInfo.Untrusted.addinsts += ac
                        ServerInfo.Untrusted.mulinsts += mc
                        ServerInfo.Untrusted.delay = max(ServerInfo.Untrusted.delay, d)

                        if l.is_native:
                            ServerInfo.Native.add += a
                            ServerInfo.Native.mul += m
                            ServerInfo.Native.rand += r
                            ServerInfo.Native.addinsts += ac
                            ServerInfo.Native.mulinsts += mc
                            ServerInfo.Native.delay = max(ServerInfo.Native.delay, d)

                    print "%s delay: %d; INVOCS: add: %d mul: %d rand: %d; INSTS: add: %d mul: %d" % (repr(l), d, a, m, r, ac, mc)

    ServerInfo.success = GiraffeCoordinator.okay
    if not GiraffeCoordinator.okay:
        print "WARNING: verification failed!"
    else:
        print "SUCCESS: verification succeeded."
    print "Native totals: INVOCS: %d add, %d mul, %d rand; INSTS: %d add, %d mul; %d max delay" % (ServerInfo.Native.add, ServerInfo.Native.mul, ServerInfo.Native.rand, ServerInfo.Native.addinsts, ServerInfo.Native.mulinsts, ServerInfo.Native.delay)
    print "Untrusted totals: INVOCS: %d add, %d mul, %d rand; INSTS: %d add, %d mul; %d max delay" % (ServerInfo.Untrusted.add, ServerInfo.Untrusted.mul, ServerInfo.Untrusted.rand, ServerInfo.Untrusted.addinsts, ServerInfo.Untrusted.mulinsts, ServerInfo.Untrusted.delay)
    print "Trusted totals: INVOCS: %d add, %d mul, %d rand; INSTS: %d add, %d mul; %d max delay" % (ServerInfo.Trusted.add, ServerInfo.Trusted.mul, ServerInfo.Trusted.rand, ServerInfo.Trusted.addinsts, ServerInfo.Trusted.mulinsts, ServerInfo.Trusted.delay)


def handle_pws():
    pws_parsed = pypws.parse_pws(ServerInfo.pws_file)
    inputs = tutil.pws2sv(pws_parsed, not ServerInfo.quiet, ServerInfo.nCopyBits, ServerInfo.nParBitsP, ServerInfo.nParBitsV, ServerInfo.nParBitsVLay, ServerInfo.plStages, ServerInfo.nParBitsPH)
    nLayers = inputs[0][1]

    if ServerInfo.rundir is None:
        outdir = os.getcwd()
    else:
        outdir = os.path.join(ServerInfo.rundir, "rtl")

    for f in os.listdir(outdir):
        if f[:8] == "frompws_":
            os.remove(os.path.join(outdir, f))

    if not ServerInfo.sweval:
        for i in range(0, nLayers):
            outfile = os.path.join(outdir, 'frompws_computation_layer_%d.sv' % i)
            open(outfile, 'w').write(computation.computation_layer(inputs, i))

    open(os.path.join(outdir, 'frompws_prover_shim.sv'), 'w').write(prover.prover_shim(inputs))
    for i in range(0, nLayers):
        outfile = os.path.join(outdir, 'frompws_prover_layer_%d.sv' % i)
        open(outfile, 'w').write(prover.prover_layer(inputs, i))

    open(os.path.join(outdir, 'frompws_verifier_input.sv'), 'w').write(verifier.verifier_input(inputs))
    open(os.path.join(outdir, 'frompws_verifier_output.sv'), 'w').write(verifier.verifier_output(inputs))
    for i in range(0, nLayers):
        outfile = os.path.join(outdir, 'frompws_verifier_layer_%d.sv' % i)
        open(outfile, 'w').write(verifier.verifier_layer(inputs, i))

    GiraffeCoordinator.initialize(inputs[0], pws_parsed, ServerInfo)


def main():
    handle_pws()
    run()


if __name__ == "__main__":
    get_params()
    Defs.debug = ServerInfo.debug
    main()
