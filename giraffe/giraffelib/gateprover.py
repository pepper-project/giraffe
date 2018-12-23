#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# gate provers

import giraffelib.util as util
from giraffelib.defs import Defs
import giraffelib.arithcircuit as ac

class _GateProver(object):
    gate_type_idx = None

    def __init__(self, isEarly, in0, in1, out, layer, muxbit=0):
        self.accum_z1 = self.accum_in0 = self.accum_in1 = None
        self.roundNum = 0
        self.layer = layer
        self.isEarly = isEarly
        self.in0 = in0
        self.in1 = in1
        self.out = out
        self.muxbit = muxbit
        self.output = []

    # reset gate prover to beginning of sumcheck
    def reset(self):
        self.accum_z1 = None
        self.roundNum = 0
        if self.isEarly:
            self.output = [0, 0, 0, 0]
            self.accum_in0 = None
            self.accum_in1 = None
        else:
            self.output = [0, 0, 0]
            self.accum_in0 = self.layer.compute_v_final.outputs[self.in0]
            self.accum_in1 = self.layer.compute_v_final.outputs[self.in1]

    # switch gate from "early" to "late" mode
    def set_early(self, isEarly):
        self.isEarly = isEarly

    # set z value from Verifier
    def set_z(self):
        self.reset()
        self.accum_z1 = self.layer.compute_z1chi.outputs[self.out]

    # update output of this gate prover
    def compute_outputs(self, *args):
        if self.isEarly:
            assert len(args) == 1
            self.compute_outputs_early(args[0])
        else:
            assert len(args) == 0
            self.compute_outputs_late()

    def compute_outputs_early(self, copy):
        assert self.roundNum < self.layer.circuit.nCopyBits
        assert (copy % 2) == 0

        # evaluate gatefn for copy and copy+1 simultaneously
        out = [0, 0, 0, 0]
        out[0] = self.gatefn(self.layer.compute_v[self.in0].outputs[copy],
                             self.layer.compute_v[self.in1].outputs[copy])
        out[0] *= self.accum_z1
        out[0] %= Defs.prime

        out[1] = self.gatefn(self.layer.compute_v[self.in0].outputs[copy+1],
                             self.layer.compute_v[self.in1].outputs[copy+1])
        out[1] *= self.accum_z1
        out[1] %= Defs.prime

        # evaluate gatefn at 3rd and 4th points
        # note that we use [copy >> 1] because compute_v has expand_outputs = False
        # note that we don't multiply by p or (1-p) because we're summing x*p + x*(1-p), which is just x
        out[2] = self.gatefn(self.layer.compute_v[self.in0].outputs_fact[0][copy >> 1],
                             self.layer.compute_v[self.in1].outputs_fact[0][copy >> 1])
        out[2] *= self.accum_z1
        out[2] %= Defs.prime

        out[3] = self.gatefn(self.layer.compute_v[self.in0].outputs_fact[1][copy >> 1],
                             self.layer.compute_v[self.in1].outputs_fact[1][copy >> 1])
        out[3] *= self.accum_z1
        out[3] %= Defs.prime

        self.output = out

    def compute_outputs_late(self):
        assert self.roundNum < 2 * self.layer.prevL.nOutBits

        # evaluate gatefn at third point (-1)
        if self.roundNum < self.layer.prevL.nOutBits:
            isOneVal = util.bit_is_set(self.in0, self.roundNum)
            leftVal = self.layer.compute_v_final.outputs_fact[0][self.in0]
            valForTwo = self.gatefn(leftVal, self.accum_in1)
        else:
            isOneVal = util.bit_is_set(self.in1, self.roundNum - self.layer.prevL.nOutBits)
            rightVal = self.layer.compute_v_final.outputs_fact[0][self.in1]
            valForTwo = self.gatefn(self.accum_in0, rightVal)

        # evaluate addmul at third point
        valForTwo *= util.third_eval_point(self.accum_z1, isOneVal)
        valForTwo %= Defs.prime

        # produce outputs for 0, 1, 2
        out = [0, 0, valForTwo]
        valForZeroOne = self.accum_z1 * self.gatefn(self.accum_in0, self.accum_in1)
        valForZeroOne %= Defs.prime
        if isOneVal:
            out[1] = valForZeroOne
        else:
            out[0] = valForZeroOne

        self.output = out

    # update values internal to this gate prover upon receiving a new tau value from V
    def next_round(self, val):
        # early rounds: no gate-internal state
        if self.isEarly:
            return

        if self.roundNum >= 2 * self.layer.prevL.nOutBits:
            # no changes after the first 2 * g' rounds
            return

        # figure out how to update GateProver's state this round
        isOneVal = False
        if self.roundNum < self.layer.prevL.nOutBits:
            ### updating omega_1 value

            # first, figure out how to update wiring predicate
            isOneVal = util.bit_is_set(self.in0, self.roundNum)

            # second, update appropriate V value
            if self.roundNum < self.layer.prevL.nOutBits - 1:
                self.accum_in0 = self.layer.compute_v_final.outputs[self.in0]
            else:
                self.accum_in0 = self.layer.compute_v_final.prevPassValue
        else:
            ### updating omega_2 value

            # first, figure out how to update wiring predicate
            isOneVal = util.bit_is_set(self.in1, self.roundNum - self.layer.prevL.nOutBits)

            # second, update appropriate V value
            if self.roundNum < 2 * self.layer.prevL.nOutBits - 1:
                self.accum_in1 = self.layer.compute_v_final.outputs[self.in1]
            else:
                self.accum_in1 = self.layer.compute_v_final.prevPassValue

        self.accum_z1 *= val if isOneVal else (1 - val)
        self.accum_z1 %= Defs.prime

        self.roundNum += 1

    def gatefn(self, x, y):
        return self.gatefn_(x, y)

    @staticmethod
    def gatefn_(*_):
        assert False

class _FirstOrderGateProver(_GateProver):
    pass

class _SecondOrderGateProver(_GateProver):
    pass

class MulGateProver(_SecondOrderGateProver):
    gate_type = "mul"
    gate_type_idx = 0
    cgate = ac.CMulGate

    @staticmethod
    def gatefn_(x, y):
        # pylint: disable=arguments-differ
        return (x * y) % Defs.prime

class AddGateProver(_FirstOrderGateProver):
    gate_type = "add"
    gate_type_idx = 1
    cgate = ac.CAddGate

    @staticmethod
    def gatefn_(x, y):
        # pylint: disable=arguments-differ
        return (x + y) % Defs.prime

class SubGateProver(_FirstOrderGateProver):
    gate_type = "sub"
    gate_type_idx = 2
    cgate = ac.CSubGate

    @staticmethod
    def gatefn_(x, y):
        # pylint: disable=arguments-differ
        return (x - y) % Defs.prime

class MuxGateProver(_FirstOrderGateProver):
    gate_type = "mux"
    # NOTE 3 and 4 are muxL and muxR, respectively
    gate_type_idx = 3
    cgate = ac.CMuxGate

    @staticmethod
    def gatefn_(x, y, bit):
        # pylint: disable=arguments-differ
        if bit:
            return y
        else:
            return x

    def gatefn(self, x, y):
        bit = self.layer.circuit.muxbits[self.muxbit]
        return self.gatefn_(bit, x, y)

# magic so that GateFunction is statically indexable
class GateFunctionsMeta(type):
    def __getitem__(cls, idx):
        return cls._gatemethods[idx]
    def __len__(cls):
        return len(cls._gatemethods)

class GateFunctions(object):
    __metaclass__ = GateFunctionsMeta

    _gatemethods = [ MulGateProver.gatefn_
                   , AddGateProver.gatefn_
                   , SubGateProver.gatefn_
                   , lambda x, y: MuxGateProver.gatefn_(x, y, False)
                   , lambda x, y: MuxGateProver.gatefn_(x, y, True)
                   ]
