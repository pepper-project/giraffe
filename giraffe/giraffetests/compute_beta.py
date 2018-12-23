#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# test LayerComputeBeta

# hack: this test lives in a subdir
import sys
import os.path
sys.path.insert(1, os.path.abspath(os.path.join(sys.path[0], os.pardir)))

from giraffelib import util
from giraffelib.defs import Defs
from giraffelib.layercompute import LayerComputeBeta

nOutBits = 4
lcv = LayerComputeBeta(nOutBits)

def run_test():
    # pylint: disable=global-variable-undefined,redefined-outer-name
    tinputs = [Defs.gen_random() for _ in range(0, nOutBits)]
    taus = [Defs.gen_random() for _ in range(0, nOutBits)]
    lcv.set_inputs(tinputs)

    inputs = [util.chi(util.numToBin(x, nOutBits), tinputs) for x in range(0, 2**nOutBits)]

    global scratch
    global outputs

    scratch = list(inputs)
    outputs = list(inputs)

    def compute_next_value(tau):
        global scratch
        global outputs

        nscratch = []
        tauInv = (1 - tau) % Defs.prime

        for i in range(0, len(scratch) / 2):
            val = ((scratch[2*i] * tauInv) + (scratch[2*i + 1] * tau)) % Defs.prime
            nscratch.append(val)

        del val
        scratch = nscratch

        #ndups = len(outputs) / len(scratch)
        #nouts = [ [val] * ndups for val in scratch ]
        outputs = scratch
        #outputs = [item for sublist in nouts for item in sublist]

    for i in range(0, nOutBits):
        assert lcv.inputs == inputs
        assert lcv.outputs == outputs
        assert lcv.scratch == scratch

        compute_next_value(taus[i])
        lcv.next_round(taus[i])

        assert outputs == lcv.outputs
        assert scratch == lcv.scratch

    assert lcv.prevPassValue == scratch[0]
    assert all([lcv.prevPassValue == elm[0] for elm in lcv.outputs_fact])

def run_tests(num_tests):
    for i in range(0, 64 * num_tests):
        run_test()
        if i % 64 == 0:
            sys.stdout.write('.')
            sys.stdout.flush()

    print " (compute_beta test passed)"

if __name__ == "__main__":
    run_tests(128)
