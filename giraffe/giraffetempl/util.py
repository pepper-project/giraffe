#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# take output from pylibpws and turn it into something we can use in giraffetemplates

import math
import os.path

# log2
def clog2(val):
    return int(math.ceil(math.log10(val)/math.log10(2)))

# load a template
def load_template(filename):
    fname = os.path.abspath(os.path.join(os.path.dirname(__file__), filename))
    with open(fname) as template:
        return template.read()

# parse a PWS file into things we'll use for templating
def pws2sv(input_pws, defDebug, nCopyBits, nParBitsP, nParBitsV, nParBitsVLay, plStages, nParBitsPH):
    input_layer = input_pws[0]
    input_pws = list(reversed(input_pws[1:]))

    nLayers = len(input_pws)
    nInputs = len(input_layer)
    nGatesLay = [ len(x) for x in input_pws ]
    nInputsLay = nGatesLay[1:] + [nInputs]
    nMuxSels = max([ max([ 0 if x[3] is None else x[3] for x in lay ]) for lay in input_pws ]) + 1
    nMuxBits = max(clog2(nMuxSels), 1)

    p_ninputs = []
    p_ngates = []
    p_gates_fn = []
    p_gates_in0 = []
    p_gates_in1 = []
    p_gates_mux = []
    for lay in range(0, nLayers):
        nInBits = clog2(nInputsLay[lay])
        maxInBit = nInBits * nGatesLay[lay] - 1
        maxMuxBit = nMuxBits * nGatesLay[lay] - 1

        p_ninputs.append("localparam nInputs = %d;" % nInputsLay[lay])
        p_ngates.append("localparam nGates = %d;" % nGatesLay[lay])

        gfn = "localparam [`GATEFN_BITS*%d-1:0] gates_fn = { " % nGatesLay[lay]
        gin0 = "localparam [%d:0] gates_in0 = { " % maxInBit
        gin1 = "localparam [%d:0] gates_in1 = { " % maxInBit
        gmux = "localparam [%d:0] gates_mux = { " % maxMuxBit

        first = True
        for gate in reversed(input_pws[lay]):
            if first:
                first = False
            else:
                gfn += ", "
                gin0 += ", "
                gin1 += ", "
                gmux += ", "

            gfn += "`GATEFN_" + gate[0]
            gin0 += "%d'd%d" % (nInBits, gate[1])
            gin1 += "%d'd%d" % (nInBits, gate[2])
            gmux += "%d'd%d" % (nMuxBits, 0 if gate[3] is None else gate[3])

        p_gates_fn.append(gfn + " };")
        p_gates_in0.append(gin0 + " };")
        p_gates_in1.append(gin1 + " };")
        p_gates_mux.append(gmux + " };")

    mklp = lambda name, value: "localparam %s = %d;" % (name, value)
    tlvals = { "nInputs":       mklp("nInputs", nInputs)
             , "nLayers":       mklp("nLayers", nLayers)
             , "nMuxSels":      mklp("nMuxSels", nMuxSels)
             , "nCopyBits":     mklp("nCopyBits", nCopyBits)
             , "nParBitsP":     mklp("nParBitsP", nParBitsP)
             , "nParBitsPH":    mklp("nParBitsPH", nParBitsPH)
             , "nParBitsV":     mklp("nParBitsV", nParBitsV)
             , "nOutputs":      mklp("nOutputs", nGatesLay[0])
             , "nParBitsVLay":  mklp("nParBitsVLay", nParBitsVLay)
             , "plStages":      mklp("plStages", plStages)
             , "defDebug":      mklp("defDebug", 1 if defDebug else 0)
             }

    coord_info = (input_layer, nLayers, nInputs, nCopyBits, nMuxSels, nParBitsP)

    return (coord_info, tlvals, p_ninputs, p_ngates, p_gates_fn, p_gates_in0, p_gates_in1, p_gates_mux)
