#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# test IO MLExt streaming algorithm (due to Victor Vu)

import sys
import os.path
sys.path.insert(1, os.path.abspath(os.path.join(sys.path[0], os.pardir)))

import random

from giraffelib.circuitverifier import VerifierIOMLExt
from giraffelib.defs import Defs, FArith
from giraffelib.layercompute import LayerComputeBeta, LayerComputeV
import giraffelib.util as util

def run_one_test(nbits, squawk, nbins, pattern):
    z = [ Defs.gen_random() for _ in range(0, nbits) ]

    inv = [ Defs.gen_random() for _ in range(0, (2 ** nbits) - nbins) ]
    if pattern is 0:
        inv += [ 0 for _ in range(0, nbins) ]
    elif pattern is 1:
        inv += [ 1 for _ in range(0, nbins) ]
    elif pattern is 2:
        inv += [ (i % 2) for i in range(0, nbins) ]
    elif pattern is 3:
        inv += [ ((i + 1) % 2) for i in range(0, nbins) ]
    else:
        inv += [ random.randint(0, 1) for _ in range(0, nbins) ]

    assert len(inv) == (2 ** nbits)

    fa = FArith()
    oldrec = fa.new_cat("old")
    newrec = fa.new_cat("new")
    nw2rec = fa.new_cat("nw2")
    nw3rec = fa.new_cat("nw3")

    oldbeta = LayerComputeBeta(nbits, z, oldrec)
    oldval = sum(util.mul_vecs(oldbeta.outputs, inv)) % Defs.prime
    oldrec.did_mul(len(inv))
    oldrec.did_add(len(inv)-1)

    newcomp = VerifierIOMLExt(z, newrec)
    newval = newcomp.compute(inv)

    nw2comp = LayerComputeV(nbits, nw2rec)
    nw2comp.other_factors = []
    nw2comp.set_inputs(inv)
    for zz in z:
        nw2comp.next_round(zz)
    nw2val = nw2comp.prevPassValue

    nw3comp = VerifierIOMLExt(z, nw3rec)
    nw3val = nw3comp.compute_sqrtbits(inv)

    assert oldval == newval, "error for inputs (new) %s : %s" % (str(z), str(inv))
    assert oldval == nw2val, "error for inputs (nw2) %s : %s" % (str(z), str(inv))
    assert oldval == nw3val, "error for inputs (nw3) %s : %s" % (str(z), str(inv))

    if squawk:
        print
        print "nbits: %d" % nbits
        print "OLD: %d mul %d add %d sub" % oldrec.get_counts()
        print "NEW: %d mul %d add %d sub" % newrec.get_counts()
        print "NW2: %d mul %d add %d sub" % nw2rec.get_counts()
        print "NW3: %d mul %d add %d sub" % nw3rec.get_counts()

    return newrec.get_counts()

def run_tests(num_tests, squawk=False):
    for _ in range(0, num_tests):
        nbits = random.randint(3, 8)
        run_one_test(nbits, squawk, 0, 0)
        if not squawk:
            sys.stdout.write('.')
            sys.stdout.flush()

    if not squawk:
        print " (iomlext test passed)"

def run_savetests():
    Defs.savebits = True
    nbits = int(sys.argv[1])
    fval = run_one_test(nbits, False, 0, 0)
    print "%d/0: %d muls, %d adds" % (nbits, fval[0], fval[1])
    print

    for lnbins in range(0, nbits + 1):
        nbins = 2 ** lnbins
        tot_m = 0
        tot_a = 0
        final = 300.0
        for _ in range(0, int(final)):
            vals = run_one_test(nbits, False, nbins, 4)
            tot_m += vals[0]
            tot_a += vals[1]

        print "%d/%d: %f muls, %f adds" % (nbits, nbins, tot_m/final, tot_a/final)
        fval = run_one_test(nbits, False, nbins, 2)
        print "%d/%d: %d muls, %d adds" % (nbits, nbins, fval[0], fval[1])
        print

if __name__ == "__main__":
    if len(sys.argv) < 2:
        run_tests(128, True)
    else:
        run_savetests()
