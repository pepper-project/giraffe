#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# circuit provers (aka provers)

import giraffelib.parse_pws
import giraffelib.util as util
from giraffelib.arithcircuitbuilder import ArithCircuitBuilder
from giraffelib.layerprover import InputLayer, LayerProver

# this is just for use with libprv_layer_test
class _DummyCircuitProver(object):
    def __init__(self, nCopies):
        self.nCopies = nCopies
        self.nCopyBits = util.clog2(nCopies)
        self.muxbits = []

class CircuitProver(object):
    __metaclass__ = giraffelib.parse_pws.FromPWS

    def __init__(self, nCopies, nInputs, in0vv, in1vv, typevv, muxvv=None):
        self.nCopies = nCopies
        self.nCopyBits = util.clog2(nCopies)
        self.nInBits = util.clog2(nInputs)
        self.ckt_inputs = []
        self.ckt_outputs = []
        self.muxbits = []
        self.layerNum = 0
        self.roundNum = 0

        assert len(in0vv) == len(in1vv)
        assert len(in0vv) == len(typevv)
        assert muxvv is None or len(in0vv) == len(muxvv)
        if muxvv is None:
            muxvv = [None] * len(in0vv)

        # build circuit and provers layer-by-layer
        self.layers = [InputLayer(self.nInBits)]
        self.arith_circuit = ArithCircuitBuilder(nCopies, nInputs, in0vv, in1vv, typevv, muxvv)
        self.arith_circuit.set_muxbits(self.muxbits)

        for (lay, (in0v, in1v, muxv, typev)) in enumerate(zip(in0vv, in1vv, muxvv, typevv)):
            # layer prover
            self.layers.append(LayerProver(self.layers[lay], self, in0v, in1v, typev, muxv))

    def set_muxbits(self, muxbits):
        assert len(muxbits) == len(self.muxbits)
        for i in range(0, len(self.muxbits)):
            self.muxbits[i] = muxbits[i]

    def set_inputs(self, inputs):
        assert len(inputs) == self.nCopies
        self.ckt_inputs = inputs
        self.ckt_outputs = []

        # record inputs to each layer prover and set inputs for each layer prover
        (self.ckt_outputs, out)  = self.arith_circuit.run(inputs)
        for i in range(0, len(self.layers) - 1):
            self.layers[i+1].set_inputs(out[i])

    def current_layer(self):
        return self.layers[len(self.layers) - 1 - self.layerNum]

    def set_z(self, z1, z2):
        self.current_layer().set_z(z1, z2)

    def next_layer(self, val):
        lay = self.current_layer()
        lay.compute_h.next_layer(val)
        z1 = lay.compute_h.z1
        z2 = lay.compute_h.w3
        self.layerNum += 1
        self.roundNum = 0
        self.set_z(z1, z2)

    def next_round(self, val):
        self.current_layer().next_round(val)

    def get_outputs(self):
        self.current_layer().compute_outputs()
        return self.current_layer().output
