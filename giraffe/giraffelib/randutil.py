#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# rand gen utilities (split from util to break circular dep)

import random

from giraffelib.defs import Defs
import giraffelib.gateprover as gp
import giraffelib.util as util

def rand_ckt(nOutBits, nInBits):
    in0v = []
    in1v = []
    typv = []

    for _ in range(0, 2**nOutBits):
        in0v.append(random.randint(0, 2**nInBits - 1))
        in1v.append(random.randint(0, 2**nInBits - 1))

        # XXX test muxes!!!
        typN = random.randint(0, 2)
        typv.append((gp.MulGateProver, gp.AddGateProver, gp.SubGateProver)[typN])

    return (in0v, in1v, typv)

def rand_inputs(nInBits, nCopies, inLay=None):
    out = []

    if inLay is None:
        inLay = [None] * (2 ** nInBits)
    else:
        nInBits = util.clog2(len(inLay))
        inLay += [0] * (2 ** nInBits - len(inLay))

    for _ in range(0, nCopies):
        out.append([ Defs.gen_random() if elm is None else elm for elm in inLay ])

    return out

def rand_str(slen):
    ostr = ""
    for _ in range(0, slen):
        cval = random.randint(0, 61)

        if cval < 26:
            ostr += chr(cval + 65)
        elif cval < 52:
            ostr += chr(cval + 71)
        else:
            ostr += str(cval - 52)

    return ostr
