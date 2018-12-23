#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# generate sv for layers of verifier

import giraffetempl.util as util

def verifier_input(inputs):
    paramstr = '\n'.join([ inputs[1][x] for x in ["nInputs", "nCopyBits", "nParBitsV", "defDebug"] ])
    top = util.load_template('verifier_input_template.sv')

    return top.format(paramstr)

def verifier_output(inputs):
    paramstr = '\n'.join([ inputs[1][x] for x in ["nCopyBits", "nParBitsV", "nOutputs", "defDebug"] ])
    top = util.load_template('verifier_output_template.sv')

    return top.format(paramstr)

def verifier_layer(inputs, layNum):
    tlvals = inputs[1]

    paramstr = '\n'.join([ tlvals[x] for x in ["nMuxSels", "nCopyBits", "nParBitsVLay", "defDebug"] ])
    paramstr += '\n' + "localparam layNum = %d;" % layNum

    for ty in inputs[2:]:
        paramstr += '\n' + ty[layNum]

    top = util.load_template('verifier_layer_template.sv')

    return top.format(paramstr, layNum)
