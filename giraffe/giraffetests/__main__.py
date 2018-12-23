#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# giraffetests runner

import sys
import os.path
sys.path.insert(1, os.path.abspath(os.path.join(sys.path[0], os.pardir)))

import giraffetests.compute_v as compute_v
import giraffetests.compute_beta as compute_beta
import giraffetests.iomlext as iomlext
import giraffetests.layer as layer
import giraffetests.circuit as circuit
import giraffetests.verifier as verifier

DEFAULT_NUM_TESTS = 32

if len(sys.argv) > 1:
    try:
        num_tests = int(sys.argv[1])
    except:
        num_tests = DEFAULT_NUM_TESTS
else:
    num_tests = DEFAULT_NUM_TESTS

compute_v.run_tests(num_tests)
compute_beta.run_tests(num_tests)
iomlext.run_tests(num_tests)
layer.run_tests(num_tests)
circuit.run_tests(num_tests)
verifier.run_tests(num_tests)
