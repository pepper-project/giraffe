#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# Python representation of arithmetic circuit elements

from giraffelib.defs import Defs
import giraffelib.util

class _CGate(object):
    def __init__(self, in0, in1, out, layer, muxb=None):
        self.in0 = int(in0)
        self.in1 = int(in1)
        self.out = int(out)
        self.layer = layer
        self.muxbit = muxb
        self.value = None

    # in this class, it does nothing
    def run(self):
        pass


class CAddGate(_CGate):
    def run(self):
        self.value = (self.layer.prevL.outputs[self.in0] + self.layer.prevL.outputs[self.in1]) % Defs.prime

class CMulGate(_CGate):
    def run(self):
        self.value = (self.layer.prevL.outputs[self.in0] * self.layer.prevL.outputs[self.in1]) % Defs.prime

class CSubGate(_CGate):
    def run(self):
        self.value = (self.layer.prevL.outputs[self.in0] - self.layer.prevL.outputs[self.in1]) % Defs.prime

class CMuxGate(_CGate):
    def run(self):
        if self.layer.circuit.muxbits[self.muxbit]:
            self.value = self.layer.prevL.outputs[self.in0]
        else:
            self.value = self.layer.prevL.outputs[self.in1]

class ArithCircuitLayer(object):
    def __init__(self, ckt, prevL, in0v, in1v, typev, muxv=None):
        self.gates = []
        self.outputs = []
        self.outputs_unpadded = []
        self.nOutBits = giraffelib.util.clog2(len(in0v))
        self.prevL = prevL
        self.circuit = ckt

        if muxv is None:
            muxv = [0] * len(in0v)

        assert len(in1v) == len(in0v)
        assert len(muxv) == len(in0v)
        assert len(typev) == len(in0v)

        max_muxbit = 0
        for (out, (in0, in1, mx, tp)) in enumerate(zip(in0v, in1v, muxv, typev)):
            assert issubclass(tp, _CGate)
            self.gates.append(tp(in0, in1, out, self, mx))
            if mx > max_muxbit:
                max_muxbit = mx

        muxlen = max_muxbit + 1
        self.circuit.muxbits += [0] * (muxlen - len(self.circuit.muxbits))

    def run(self):
        assert len(self.prevL.outputs) == 2**self.prevL.nOutBits

        out = []
        for g in self.gates:
            g.run()
            out.append(g.value)

        self.outputs_unpadded = out
        self.outputs = out + [0] * (2**self.nOutBits - len(out))
        assert len(self.outputs) == 2**self.nOutBits

class ArithCircuitInputLayer(object):
    def __init__(self, ckt, nOutBits):
        self.nOutBits = nOutBits
        self.outputs_unpadded = []
        self.outputs = []
        self.circuit = ckt

    def run(self):
        pass

    def setInputs(self, values):
        self.outputs_unpadded = list(values)
        self.outputs = list(values) + [0] * (2**self.nOutBits - len(values))
        assert len(self.outputs) == 2**self.nOutBits

class ArithCircuit(object):
    def __init__(self, muxbits=None):
        self.layers = []
        self.inputs = []
        self.outputs = []
        self.outputs_unpadded = []
        if muxbits is not None:
            self.muxbits = muxbits
        else:
            self.muxbits = []

    def run(self, inputs):
        self.inputs = inputs
        self.layers[0].setInputs(self.inputs)
        for l in self.layers:
            l.run()
        self.outputs = self.layers[-1].outputs
        self.outputs_unpadded = self.layers[-1].outputs_unpadded
