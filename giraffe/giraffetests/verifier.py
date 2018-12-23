#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# test layer prover

# hack: this test lives in a subdir
import sys
import os.path
sys.path.insert(1, os.path.abspath(os.path.join(sys.path[0], os.pardir)))

import random

from giraffelib.circuitverifier import CircuitVerifier
from giraffelib import randutil

def run_one_test(nInBits, nCopies, nLayers, qStat):
    nOutBits = nInBits

    in0vv = []
    in1vv = []
    typvv = []
    for _ in range(0, nLayers):
        (in0v, in1v, typv) = randutil.rand_ckt(nOutBits, nInBits)
        in0vv.append(in0v)
        in1vv.append(in1v)
        typvv.append(typv)

    ver = CircuitVerifier(nCopies, 2**nInBits, in0vv, in1vv, typvv)
    ver.build_prover()
    inputs = randutil.rand_inputs(nInBits, nCopies)
    ver.run(inputs)

    if not qStat:
        print "nInBits: %d, nCopies: %d, nLayers: %d" % (nInBits, nCopies, nLayers)
        for fArith in [ver.in_a, ver.out_a, ver.sc_a, ver.tV_a, ver.nlay_a]:
            print ("    %s: %%d mul, %%d add, %%d sub" % fArith.cat) % fArith.get_counts()

def run_tests(num_tests, qStat=True):
    for _ in range(0, num_tests):
        run_one_test(random.randint(2, 4), 2**random.randint(3, 8), random.randint(2, 5), qStat)

        if qStat:
            sys.stdout.write('.')
            sys.stdout.flush()

    if qStat:
        print " (verifier test passed)"

if __name__ == "__main__":
    run_tests(16, False)
