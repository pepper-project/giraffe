#!/usr/bin/python2.7

import fcntl
import math
import random
import socket

from vpintf.defs import Defs
import vpintf.socket_nb as socket_nb

###
#  listen on a socket, maybe SSLizing
###
def listen_socket(addr, port, nlisten=16):
    ls = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

    # reuseaddr
    ls.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    # close-on-exec
    flags = fcntl.fcntl(ls.fileno(), fcntl.F_GETFD)
    flags |= fcntl.FD_CLOEXEC
    fcntl.fcntl(ls.fileno(), fcntl.F_SETFD, flags)

    ls.bind((addr, port))
    ls.listen(nlisten)
    ls.setblocking(False)
    return ls

###
#  accept from a listening socket and hand back a SocketNB
###
def accept_socket(lsock):
    (ns, _) = lsock.accept()
    ns.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    ns.setblocking(False)
    ns = socket_nb.SocketNB(ns)
    return ns

###
#  ceiling log_2
###
def clog2(val):
    return int(math.ceil(math.log10(val)/math.log10(2)))

###
#  random bit vector
###
def random_bitvec(nbits):
    retval = []
    val = random.getrandbits(nbits)

    andval = 1
    for _ in range(0, nbits):
        if val & andval != 0:
            retval.append(1)
        else:
            retval.append(0)
        andval = andval << 1

    return retval

###
#  random field element
###
def random_felem():
    retval = random.getrandbits(clog2(Defs.prime + 1))
    while retval >= Defs.prime:
        retval = random.getrandbits(clog2(Defs.prime + 1))

    return retval
