#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# take output from pylibpws and turn it into something we can use in giraffelib

from giraffelib.gateprover import MulGateProver, AddGateProver, SubGateProver, MuxGateProver

def parse_pws(input_pws):
    input_layer = input_pws[0]
    input_pws = input_pws[1:]

    in0vv = []
    in1vv = []
    typvv = []
    muxvv = []
    for lay in range(0, len(input_pws)):
        in0v = []
        in1v = []
        typv = []
        muxv = []

        for (gStr, in0, in1, mx) in input_pws[lay]:
            in0v.append(in0)
            in1v.append(in1)
            muxv.append(mx if mx is not None else 0)

            if gStr == 'ADD':
                typv.append(AddGateProver)
            elif gStr == 'MUL':
                typv.append(MulGateProver)
            elif gStr == 'SUB':
                typv.append(SubGateProver)
            elif gStr == 'MUX':
                typv.append(MuxGateProver)
            else:
                assert False, "Unknown gate type %s" % gStr

        in0vv.append(in0v)
        in1vv.append(in1v)
        typvv.append(typv)
        muxvv.append(muxv)

    return (input_layer, in0vv, in1vv, typvv, muxvv)

# circuitverifier and circuitprover use this as their metaclass
class FromPWS(type):
    def from_pws(cls, input_pws, nCopies):
        (input_layer, in0vv, in1vv, typvv, muxvv) = parse_pws(input_pws)
        return (input_layer, cls(nCopies, len(input_layer), in0vv, in1vv, typvv, muxvv))
