#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# run Giraffe given a PWS file

import getopt
import os
import sys

try:
    import pypws
except ImportError:
    print "ERROR: could not import pypws; you should run `make`. Giving up now."
    sys.exit(1)

import giraffelib.circuitverifier as cver
import giraffelib.randutil as randutil
import giraffelib.util as util

class VerifierInfo(object):
    nCopyBits = 1
    nCopies = 2
    pwsFile = None
    inputFile = None

def get_usage():
    uStr =  "Usage: %s [-c <nCopyBits>] [-i <inputsFile>] -p <pwsFile>\n\n" % sys.argv[0]
    uStr += " option        description                                 default\n"
    uStr += " --            --                                          --\n"

    uStr += " -p pwsFile:   PWS describing the computation to run.      (None)\n"

    uStr += " -c nCopyBits: log2(#copies) to verify in parallel         (%d)\n" % VerifierInfo.nCopyBits

    uStr += " -i inputFile: file containing inputs for each copy        (None)\n"
    uStr += "               (otherwise, inputs are generated at random\n"

    return uStr

def get_inputs(verifier_info, input_layer):
    if verifier_info.inputFile is None:
        return randutil.rand_inputs(0, verifier_info.nCopies, input_layer)

    if not os.path.isfile(verifier_info.inputFile):
        print "ERROR: cannot find input file '%s'" % verifier_info.inputFile
        sys.exit(1)

    with open(verifier_info.inputFile, 'r') as inF:
        inputs = []
        nLines = 0
        nVarInputs = len([ 1 for elm in input_layer if elm is None ])
        for line in inF:
            line.strip()
            inLine = []
            try:
                values = [ int(val) for val in line.split(None) ]

                assert len(values) == nVarInputs, "expected %d, got %d (#1)" % (nVarInputs, len(values))

                vidx = 0
                for idx in range(0, len(input_layer)):
                    if input_layer[idx] is None:
                        inLine.append(values[vidx])
                        vidx += 1
                    else:
                        inLine.append(input_layer[idx])

                assert vidx == len(values), "expected %d, got %d (#2)" % (len(values), vidx)
                assert len(inLine) == len(input_layer), "expected %d, got %d (#3)" % (len(input_layer), len(inLine))

            except AssertionError as ae:
                print "ERROR: inputFile has the wrong number of variables:", str(ae)
                sys.exit(1)
            except ValueError as ve:
                print "ERROR: could not parse inputFile value:", str(ve)
                sys.exit(1)

            inputs.append(inLine)

            nLines += 1
            if nLines == VerifierInfo.nCopies:
                break

    if len(inputs) != VerifierInfo.nCopies:
        print "ERROR: inputFile has too few lines (got %d, expected %d)" % (len(inputs), VerifierInfo.nCopies)
        sys.exit(1)

    return inputs

def run_giraffe(verifier_info):
    # pylint doesn't seed to understand how classmethods are inherited from metclasses
    from_pws = cver.CircuitVerifier.from_pws # pylint: disable=no-member

    (input_layer, ver) = from_pws(pypws.parse_pws(verifier_info.pwsFile), verifier_info.nCopies)
    ver.build_prover()

    inputs = get_inputs(verifier_info, input_layer)
    ver.run(inputs)

    nInBits = util.clog2(len(input_layer))
    nCopies = VerifierInfo.nCopies
    nLayers = len(ver.in0vv)
    print "nInBits: %d, nCopies: %d, nLayers: %d" % (nInBits, nCopies, nLayers)
    (tMul, tAdd, tSub) = (0, 0, 0)
    for fArith in [ver.in_a, ver.out_a, ver.sc_a, ver.tV_a, ver.nlay_a]:
        (mul, add, sub) = fArith.get_counts()
        tMul += mul
        tAdd += add
        tSub += sub
        print "    %s: %d mul, %d add, %d sub" % (fArith.cat, mul, add, sub)

    print "  TOTAL: %d mul, %d add, %d sub" % (tMul, tAdd, tSub)

    lcosts = ver.local_costs()
    print "  LOCAL: %d mul, %d add, %d sub" % (lcosts.get('mul', 0), lcosts.get('add', 0), lcosts.get('sub', 0))

def main():
    uStr = get_usage()
    oStr = "c:i:p:"

    try:
        (opts, args) = getopt.getopt(sys.argv[1:], oStr)
    except getopt.GetoptError as err:
        print uStr
        print str(err)
        sys.exit(1)

    if len(args) > 0:
        print uStr
        print "ERROR: extraneous arguments."
        sys.exit(1)

    for (opt, arg) in opts:
        if opt == "-c":
            nCB = int(arg)
            VerifierInfo.nCopyBits = nCB
            VerifierInfo.nCopies = 1 << nCB
        elif opt == "-i":
            VerifierInfo.inputFile = arg
        elif opt == "-p":
            VerifierInfo.pwsFile = arg
        else:
            assert False, "logic error: got unexpected option %s from getopt" % opt

    if VerifierInfo.pwsFile is None:
        print uStr
        print "ERROR: missing required argument, -p <pwsFile>."
        sys.exit(1)

    if VerifierInfo.nCopyBits < 1:
        print uStr
        print "ERROR: nCopyBits must be at least 1."
        sys.exit(1)

    run_giraffe(VerifierInfo)

if __name__ == "__main__":
    main()
