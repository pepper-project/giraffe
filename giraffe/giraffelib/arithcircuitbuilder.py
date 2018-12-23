#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# Python representation of arithmetic circuit elements

from giraffelib.arithcircuit import ArithCircuit, ArithCircuitInputLayer, ArithCircuitLayer, CAddGate, CMulGate, CSubGate
import giraffelib.parse_pws
import giraffelib.util

class ArithCircuitBuilder(object):
    __metaclass__ = giraffelib.parse_pws.FromPWS

    def __init__(self, nCopies, nInputs, in0vv, in1vv, typevv, muxvv=None):
        nInBits = giraffelib.util.clog2(nInputs)

        assert len(in0vv) == len(in1vv) and len(in0vv) == len(typevv) and (muxvv is None or len(in0vv) == len(muxvv))
        if muxvv is None:
            muxvv = [None] * len(in0vv)

        arith_circuit = ArithCircuit()
        arith_circuit.layers = [ArithCircuitInputLayer(arith_circuit, nInBits)]
        for (lay, (in0v, in1v, muxv, typev)) in enumerate(zip(in0vv, in1vv, muxvv, typevv)):
            typec = [ typ.cgate for typ in typev ]
            arith_circuit.layers.append(ArithCircuitLayer(arith_circuit, arith_circuit.layers[lay], in0v, in1v, typec, muxv))

        self.arith_circuit = arith_circuit
        self.nCopies = nCopies

    def get_counts(self):
        counts = []
        for lay in self.arith_circuit.layers[1:]:
            l_count = [0, 0, 0, 0]
            for gate in lay.gates:
                if isinstance(gate, CAddGate):
                    l_count[0] += self.nCopies
                    l_count[2] += 1
                elif isinstance(gate, CSubGate):
                    l_count[0] += 2 * self.nCopies
                    l_count[2] += 1
                elif isinstance(gate, CMulGate):
                    l_count[1] += self.nCopies
                    l_count[3] += 1
            counts.append(l_count)
        return counts

    def set_muxbits(self, muxbits):
        self.arith_circuit.muxbits = muxbits

    def run(self, inputs, padded=True):
        assert len(inputs) == self.nCopies

        # record inputs to each layer prover
        out = [ list() for _ in range(0, len(self.arith_circuit.layers) - 1) ]
        ckt_outputs = []
        for inp in inputs:
            self.arith_circuit.run(inp)
            ckt_outputs.append(self.arith_circuit.outputs if padded else self.arith_circuit.outputs_unpadded)
            for (idx, lay) in enumerate(self.arith_circuit.layers[:-1]):
                out[idx].append(lay.outputs if padded else lay.outputs_unpadded)

        return (ckt_outputs, out)
