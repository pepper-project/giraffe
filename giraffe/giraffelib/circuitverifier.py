#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# verifier

import giraffelib.parse_pws
import giraffelib.util as util
from giraffelib.defs import Defs, FArith
from giraffelib.circuitprover import CircuitProver
from giraffelib.gateprover import GateFunctions

class CircuitVerifier(object):
    __metaclass__ = giraffelib.parse_pws.FromPWS

    def __init__(self, nCopies, nInputs, in0vv, in1vv, typvv, muxvv=None):
        self.nCopies = nCopies
        self.nCopyBits = util.clog2(nCopies)
        self.nInputs = nInputs
        self.nInBits = util.clog2(nInputs)
        self.prover = None
        self.in0vv = in0vv
        self.in1vv = in1vv
        self.typvv = typvv
        self.muxvv = muxvv
        self.muxbits = None
        self.inputs = []
        self.outputs = []

        fArith = FArith()
        self.in_a = fArith.new_cat("v_in")
        self.out_a = fArith.new_cat("v_out")
        self.sc_a = fArith.new_cat("v_sc")
        self.tV_a = fArith.new_cat("v_tv")
        self.nlay_a = fArith.new_cat("v_nlay")

        # nOutBits and nInBits for each layer
        self.layOutBits = [ util.clog2(len(lay)) for lay in reversed(self.in0vv) ]
        self.layInBits = self.layOutBits[1:] + [self.nInBits]

    def local_costs(self):
        gate_types = {}

        for typv in self.typvv:
            for typ in typv:
                attrName = getattr(typ, 'gate_type', None)
                gate_types[attrName] = 1 + gate_types.get(attrName, 0)

        for gtype in gate_types:
            gate_types[gtype] *= self.nCopies

        return gate_types

    def build_prover(self):
        self.set_prover(CircuitProver(self.nCopies, self.nInputs, self.in0vv, self.in1vv, self.typvv, self.muxvv))
        return self.prover

    def set_prover(self, prover):
        self.prover = prover

    def run(self, inputs, muxbits=None):
        ############
        # 0. Setup #
        ############
        assert self.prover is not None

        # set inputs and outputs
        self.prover.set_inputs(inputs)
        self.inputs = []
        for ins in inputs:
            self.inputs.extend(ins + [0] * (2**self.nInBits - len(ins)))
        self.outputs = util.flatten(self.prover.ckt_outputs)

        # set muxbits
        self.muxbits = muxbits
        if muxbits is not None:
            self.prover.set_muxbits(muxbits)

        ###############################################
        # 1. Compute multilinear extension of outputs #
        ###############################################
        nOutBits = util.clog2(len(self.in0vv[-1]))
        assert util.clog2(len(self.outputs)) == nOutBits + self.nCopyBits

        # pad out to power-of-2 number of copies
        self.outputs += [0] * (2 ** (nOutBits + self.nCopyBits) - len(self.outputs))

        # generate random point in (z1, z2) \in F^{nOutBits + nCopyBits}
        z1 = [ Defs.gen_random() for _ in range(0, nOutBits) ]
        z2 = [ Defs.gen_random() for _ in range(0, self.nCopyBits) ]
        self.prover.set_z(z1, z2)

        # eval mlext of output at (z1,z2)
        output_mlext = VerifierIOMLExt(z1 + z2, self.out_a)
        expectNext = output_mlext.compute(self.outputs)

        ##########################################
        # 2. Interact with prover for each layer #
        ##########################################
        for lay in range(0, len(self.in0vv)):
            nInBits = self.layInBits[lay]
            nOutBits = self.layOutBits[lay]

            # random coins for this round
            w3 = [ Defs.gen_random() for _ in range(0, self.nCopyBits) ]
            w1 = [ Defs.gen_random() for _ in range(0, nInBits) ]
            w2 = [ Defs.gen_random() for _ in range(0, nInBits) ]

            # convenience
            ws = w3 + w1 + w2

            ###################
            ### A. Sumcheck ###
            ###################
            for rd in range(0, 2 * nInBits + self.nCopyBits):
                # get output from prv and check against expected value
                outs = self.prover.get_outputs()
                gotVal = (outs[0] + sum(outs)) % Defs.prime
                self.sc_a.did_add(len(outs))

                assert expectNext == gotVal, "Verification failed in round %d of layer %d" % (rd, lay)

                # go to next round
                self.prover.next_round(ws[rd])
                expectNext = util.horner_eval(outs, ws[rd], self.sc_a)

            outs = self.prover.get_outputs()
            v1 = outs[0] % Defs.prime
            v2 = sum(outs) % Defs.prime
            self.tV_a.did_add(len(outs)-1)

            ############################################
            ### B. Evaluate mlext of wiring predicates #
            ############################################
            tV_eval = self.eval_mlext(lay, z1, z2, w1, w2, w3, v1, v2)

            # check that we got the correct value from the last round of the sumcheck
            assert expectNext == tV_eval, "Verification failed computing tV for layer %d" % lay

            ###############################
            ### C. Extend to next layer ###
            ###############################
            tau = Defs.gen_random()
            if lay < len(self.in0vv) - 1:
                self.prover.next_layer(tau)
            expectNext = util.horner_eval(outs, tau, self.nlay_a)

            # next z values
            # z1 = w1 + ( w2 - w1 ) * tau; z2 is just w3
            z1 = [ (elm1 + (elm2 - elm1) * tau) % Defs.prime for (elm1, elm2) in zip(w1, w2) ]
            self.nlay_a.did_sub(len(w1))
            self.nlay_a.did_mul(len(w1))
            self.nlay_a.did_add(len(w1))
            z2 = w3

        ##############################################
        # 3. Compute multilinear extension of inputs #
        ##############################################
        # Finally, evaluate mlext of input at z1, z2
        assert util.clog2(len(self.inputs)) == self.nInBits + self.nCopyBits
        self.inputs += [0] * (2 ** (self.nInBits + self.nCopyBits) - len(self.inputs))
        input_mlext = VerifierIOMLExt(z1 + z2, self.in_a)
        input_mlext_eval = input_mlext.compute(self.inputs)

        assert input_mlext_eval == expectNext, "Verification failed checking input mlext"

    ######################################
    # Evaluate of g_{z1, z2}(w3, w1, w2) #
    ######################################
    def eval_mlext(self, lay, z1, z2, w1, w2, w3, v1, v2):
        nInBits = self.layInBits[lay]
        nOutBits = self.layOutBits[lay]
        nCopyBits = self.nCopyBits

        assert len(z1) == nOutBits and len(z2) == nCopyBits
        assert len(w1) == nInBits and len(w2) == nInBits and len(w3) == nCopyBits

        # z1, w1, w2 factors
        mlx_z1 = VerifierIOMLExt.compute_beta(z1, self.tV_a)
        mlx_w1 = VerifierIOMLExt.compute_beta(w1, self.tV_a)
        mlx_w2 = VerifierIOMLExt.compute_beta(w2, self.tV_a)

        # beta factor (z2 and w3)
        mlx_z2 = 1
        for (w, z) in zip(w3, z2):
            tmp = 2 * w * z + 1 - (w + z)
            mlx_z2 *= tmp
            mlx_z2 %= Defs.prime
        self.tV_a.did_add(4*len(w3))
        self.tV_a.did_mul(2*len(w3)-1)

        layN = -1 - lay # idx into in0vv, etc
        mlext_evals = [0] * len(GateFunctions)
        for (out, (in0, in1, typ)) in enumerate(zip(self.in0vv[layN], self.in1vv[layN], self.typvv[layN])):
            # evaluate this gate's wiring predicate's multilinear extension
            tval = (mlx_z1[out] * mlx_w1[in0] * mlx_w2[in1]) % Defs.prime

            # figure out the gate's type
            typeidx = typ.gate_type_idx
            if typeidx == 3:
                if self.muxvv is not None:
                    mux = self.muxvv[layN][out]
                    muxb = 1 if self.muxbits[layN][mux] else 0
                    typeidx += muxb

            # store
            mlext_evals[typeidx] += tval
            mlext_evals[typeidx] %= Defs.prime
        self.tV_a.did_mul(2*len(self.in0vv[layN]))
        self.tV_a.did_add(len(self.in0vv[layN]))

        # evaluate \tV
        tV_eval = 0
        for (idx, elm) in enumerate(mlext_evals):
            tV_eval += elm * GateFunctions[idx](v1, v2)
            tV_eval %= Defs.prime
        tV_eval *= mlx_z2
        tV_eval %= Defs.prime
        self.tV_a.did_add(len(mlext_evals)-1)
        self.tV_a.did_mul(len(mlext_evals)+1)

        return tV_eval

class VerifierIOMLExt(object):
    z_vals = None
    mzp1_vals = None
    rec = None

    def __init__(self, z, rec=None):
        self.rec = rec
        self.z_vals = list(z)
        self.mzp1_vals = [ (1 - x) % Defs.prime for x in z ]

        if len(z) < 3:
            if Defs.savebits:
                self.compute = self.compute_savebits
            else:
                self.compute = self.compute_nosavebits
        else:
            self.compute = self.compute_sqrtbits

        if self.rec is not None:
            self.rec.did_add(len(z))

    def compute_nosavebits(self, inputs):
        assert len(inputs) <= 2 ** len(self.z_vals) and len(inputs) > 2 ** (len(self.z_vals) - 1)
        inputs = inputs + [0] * ((2 ** len(self.z_vals)) - len(inputs))

        intermeds = [None] * len(self.z_vals)
        total_adds = 0
        total_muls = 0
        retval = None
        for (idx, val) in enumerate(inputs):
            for i in range(0, len(intermeds)):
                if util.bit_is_set(idx, i):
                    chi = self.z_vals[i]
                else:
                    chi = self.mzp1_vals[i]
                val *= chi
                val %= Defs.prime
                total_muls += 1

                if intermeds[i] is None:
                    intermeds[i] = val
                    break
                else:
                    val = (val + intermeds[i]) % Defs.prime
                    total_adds += 1
                    intermeds[i] = None

                if i == len(intermeds) - 1:
                    retval = val

        if self.rec is not None:
            self.rec.did_add(total_adds)
            self.rec.did_mul(total_muls)

        return retval

    def compute_savebits(self, inputs):
        assert len(inputs) <= 2 ** len(self.z_vals) and len(inputs) > 2 ** (len(self.z_vals) - 1)
        inputs = inputs + [0] * ((2 ** len(self.z_vals)) - len(inputs))

        intermeds = [None] * len(self.z_vals)
        total_adds = 0
        total_muls = 0
        retval = None
        for (idx, val) in enumerate(inputs):
            if val is 0:
                val = (0, None)
            elif val is 1:
                val = (1, None)
            else:
                val = (None, val)

            for i in range(0, len(intermeds)):
                if util.bit_is_set(idx, i):
                    chi = self.z_vals[i]
                else:
                    chi = self.mzp1_vals[i]

                if val[0] is 0:
                    pass
                elif val[0] is 1:
                    val = (1, chi)
                else:
                    val = (None, (val[1] * chi) % Defs.prime)
                    total_muls += 1

                if intermeds[i] is None:
                    intermeds[i] = val
                    break
                else:
                    val2 = intermeds[i]
                    intermeds[i] = None

                    if val[0] is 1:
                        if val2[0] is 1:
                            nval = (1, None)
                        elif val2[0] is 0:
                            nval = (None, val[1])
                        else:
                            nval = (None, (val[1] + val2[1]) % Defs.prime)
                            total_adds += 1

                    elif val[0] is 0:
                        if val2[0] is 0:
                            nval = (0, None)
                        else:
                            nval = (None, val2[1])

                    else:
                        if val2[0] is 0:
                            nval = val
                        else:
                            nval = (None, (val[1] + val2[1]) % Defs.prime)
                            total_adds += 1

                    val = nval

                if i == len(intermeds) - 1:
                    retval = val[1]

        if self.rec is not None:
            self.rec.did_add(total_adds)
            self.rec.did_mul(total_muls)

        return retval

    def compute_sqrtbits(self, inputs):
        assert len(inputs) <= 2 ** len(self.z_vals) and len(inputs) > 2 ** (len(self.z_vals) - 1)
        inputs = inputs + [0] * ((2 ** len(self.z_vals)) - len(inputs))

        zlen = len(self.z_vals)
        first_half = self.z_vals[:zlen//2]
        second_half = self.z_vals[zlen-zlen//2-zlen%2:]

        if len(first_half) > 0:
            # compute first-half zvals
            fhz = VerifierIOMLExt.compute_beta(first_half, self.rec)
            second_ins = []
            for i in range(0, 2 ** len(second_half)):
                accum = 0
                addmul = 0
                for (f, inp) in zip(fhz, inputs[i*len(fhz):(i+1)*len(fhz)]):
                    if inp != 0:
                        accum += f * inp
                        accum %= Defs.prime
                        addmul += 1
                second_ins.append(accum)
                if self.rec is not None:
                    self.rec.did_mul(addmul)
                    self.rec.did_add(addmul)
        else:
            second_ins = inputs

        return VerifierIOMLExt(second_half, self.rec).compute(second_ins)

    @classmethod
    def compute_beta(cls, z, rec=None):
        # once it's small enough, just compute directly
        if len(z) == 2:
            ret = []
            omz0 = (1 - z[0]) % Defs.prime
            omz1 = (1 - z[1]) % Defs.prime

            if rec is not None:
                rec.did_sub(2)
                rec.did_mul(4)

            return [(omz0 * omz1) % Defs.prime,
                    (z[0] * omz1) % Defs.prime,
                    (omz0 * z[1]) % Defs.prime,
                    (z[0] * z[1]) % Defs.prime]

        elif len(z) == 1:
            if rec is not None:
                rec.did_sub(1)

            return [(1 - z[0]) % Defs.prime, z[0]]

        elif len(z) == 0:
            return []

        # otherwise, use recursive sqrt trick
        fh = cls.compute_beta(z[:len(z)//2], rec)
        sh = cls.compute_beta(z[len(z)//2:], rec)

        # cartesian product
        retval = []
        for s in sh:
            retval.extend([ s * f % Defs.prime for f in fh ])

        return retval
