#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# layer provers (aka sub-provers)

from giraffelib.defs import Defs
import giraffelib.util as util
import giraffelib.gateprover as gateprover
from giraffelib.layercompute import LayerComputeV, LayerComputeBeta, LayerComputeH

class InputLayer(object):
    def __init__(self, nOutBits):
        self.nOutBits = nOutBits

class LayerProver(object):
    def __init__(self, prevL, circuit, in0v, in1v, typev, muxv=None):
        # pylint: disable=protected-access
        self.prevL = prevL
        self.circuit = circuit
        self.nOutBits = util.clog2(len(in0v))
        self.roundNum = 0

        self.compute_v = []
        self.inputs = []
        self.output = []
        self.z2_save = []

        if muxv is None:
            # fake it
            muxv = [0] * len(in0v)
        assert len(in0v) == len(in1v) and len(in0v) == len(muxv) and len(in0v) == len(typev)

        # h computation subckt
        self.compute_h = LayerComputeH(self)

        # beta computation subckt
        self.compute_beta = LayerComputeBeta(self.circuit.nCopyBits)

        # z1chi computation subckt
        # this just takes advantage of the code in LayerComputeBeta
        # that does the dynamic-programming computation
        self.compute_z1chi = LayerComputeBeta(self.nOutBits)

        # v circuits are per-input---we collapse inputs in first nCopyBits rounds
        for _ in range(0, 2 ** self.prevL.nOutBits):
            lcv_tmp = LayerComputeV(self.circuit.nCopyBits)
            # outputs are collapsed
            lcv_tmp.expand_outputs = lcv_tmp.multiple_passes = False
            self.compute_v.append(lcv_tmp)

        # after finishing the first nCopyBits rounds, we only need one ComputeV circuit,
        # and everything is now 2nd order, so we only need three eval points, not four
        self.compute_v_final = LayerComputeV(self.prevL.nOutBits)
        self.compute_v_final.set_other_factors([util.THIRD_EVAL_POINT])

        # pergate computation subckts for "early" rounds
        self.gates = []
        max_muxbit = 0
        for (out, (in0, in1, mx, tp)) in enumerate(zip(in0v, in1v, muxv, typev)):
            assert issubclass(tp, gateprover._GateProver)
            self.gates.append(tp(True, in0, in1, out, self, mx))
            if mx > max_muxbit:
                max_muxbit = mx
        muxlen = max_muxbit + 1
        self.circuit.muxbits += [0] * (muxlen - len(self.circuit.muxbits))

    # set new inputs
    def set_inputs(self, inputs):
        assert len(inputs) == self.circuit.nCopies, "Got inputs for the wrong #copies"
        self.inputs = inputs
        for inX in range(0, 2 ** self.prevL.nOutBits):
            # transpose input matrix
            inXVals = [ inCopy[inX] for inCopy in inputs ]
            self.compute_v[inX].set_inputs(inXVals)

    # set a new z vector
    def set_z(self, z1, z2):
        self.roundNum = 0
        self.compute_z1chi.set_inputs(z1)
        self.compute_beta.set_inputs(z2)
        self.z2_save = list(z2)

        # loop over all the gates and make them update their z coeffs
        for g in self.gates:
            g.set_z()

    # compute fj[0], fj[1], fj[-1], and maybe fj[2]
    def compute_outputs(self):
        # if we're at the last round, just return h coefficients
        if self.roundNum == self.circuit.nCopyBits + 2 * self.prevL.nOutBits:
            self.output = self.compute_h.output
            return

        inEarlyRounds = True
        if self.roundNum >= self.circuit.nCopyBits:
            inEarlyRounds = False

        if inEarlyRounds:
            # go through each copy of the circuit
            out = [0, 0, 0, 0]
            for copy in range(0, len(self.compute_beta.outputs), 2):
                vals = [0, 0, 0, 0]
                # go through each gate, summing contribution from this copy
                for g in self.gates:
                    g.compute_outputs(copy)
                    for j in range(0, 4):
                        vals[j] += g.output[j]
                        vals[j] %= Defs.prime

                vals[0] *= self.compute_beta.outputs[copy]
                vals[0] %= Defs.prime
                out[0] += vals[0]
                out[0] %= Defs.prime

                vals[1] *= self.compute_beta.outputs[copy+1]
                vals[1] %= Defs.prime
                out[1] += vals[1]
                out[1] %= Defs.prime

                # index with [copy >> 1] because expand_outputs is false in compute_beta
                vals[2] *= self.compute_beta.outputs_fact[0][copy >> 1]
                vals[2] %= Defs.prime
                out[2] += vals[2]
                out[2] %= Defs.prime

                vals[3] *= self.compute_beta.outputs_fact[1][copy >> 1]
                vals[3] %= Defs.prime
                out[3] += vals[3]
                out[3] %= Defs.prime

            self.output = util.interpolate_cubic(out)

        else:
            # late rounds: only one set of gates over which to sum;
            # in these rounds we are updating w1 and then w2
            out = [0, 0, 0]
            for g in self.gates:
                g.compute_outputs()
                # sum contributions from this gate
                for j in range(0, 3):
                    out[j] += g.output[j]
                    out[j] %= Defs.prime

            for j in range(0, 3):
                out[j] *= self.compute_beta.prevPassValue

            self.output = util.interpolate_quadratic(out)

    # do updates upon receiving new random value
    def next_round(self, val):
        assert self.roundNum < self.circuit.nCopyBits + 2 * self.prevL.nOutBits

        inLateRounds = True
        # do beta and V updates
        if self.roundNum < self.circuit.nCopyBits:
            inLateRounds = False
            self.compute_beta.next_round(val)
            for cv in self.compute_v:
                cv.next_round(val)
            # no gate updates in early rounds: gate circuits don't update state

        # gotta do some juggling now that we're done with the w3 updates
        if self.roundNum == self.circuit.nCopyBits - 1:
            # set up compute_v_final with prevPassValues from the per-input compute_v instances
            inputs = [ cv.prevPassValue for cv in self.compute_v ]
            assert all([ elm is not None for elm in inputs ])
            self.compute_v_final.set_inputs(inputs)

            # prepare gates for final rounds
            for g in self.gates:
                g.set_early(False)
                g.set_z()

        # updating w1 or w2, which requires updating compute_v_final and the gates
        if inLateRounds:
            self.compute_v_final.next_round(val)
            for g in self.gates:
                g.next_round(val)

        # finally, update the h_vals (needs to be done after compute_v and compute_beta are updated)
        self.compute_h.next_round(val)

        self.roundNum += 1
