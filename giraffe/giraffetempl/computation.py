#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# generate sv for computation layer

import giraffetempl.util as util

def computation_layer(inputs, layNum):
    tlvals = inputs[1]

    paramstr = '\n'.join([ tlvals[x] for x in ["nMuxSels", "nCopyBits", "nParBitsP", "defDebug"] ])
    paramstr += '\n' + "localparam layNum = %d;" % layNum

    for ty in inputs[2:]:
        paramstr += '\n' + ty[layNum]

    top = util.load_template('computation_layer_template.sv')

    return top.format(paramstr, layNum)
