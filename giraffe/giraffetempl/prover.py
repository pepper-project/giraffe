#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# generate sv for prover

import giraffetempl.util as util

def prover_layer(inputs, layNum):
    tlvals = inputs[1]

    paramstr = '\n'.join([ tlvals[x] for x in ["nMuxSels", "nCopyBits", "nParBitsP", "plStages", "defDebug", "nParBitsPH"] ])
    paramstr += '\n' + "localparam layNum = %d;" % layNum

    for ty in inputs[2:]:
        paramstr += '\n' + ty[layNum]

    top = util.load_template('prover_layer_template.sv')

    return top.format(paramstr, layNum)

def prover_shim(inputs):
    paramstr = '\n'.join([ inputs[1][x] for x in ["nCopyBits", "nOutputs", "defDebug"] ])
    top = util.load_template('prover_shim_template.sv')

    return top.format(paramstr)
