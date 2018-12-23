#!/usr/bin/python2.7

# generate optimized convolution circuit using nttopt

import os
import subprocess
import re
import sys
import tempfile

import nttopt

pwsexec = os.path.abspath(os.path.join(os.path.dirname(__file__), "../libpws/src/pwsrepeat/pwsrepeat"))
if not os.path.exists(pwsexec):
    print "ERROR: you need to build libpws first! See src/libpws/README.md."
    sys.exit(1)


def run_nttopt():
    # redirect stdout to a tempfile
    (tfd, tfile) = tempfile.mkstemp()
    oldstdout = sys.stdout
    sys.stdout = os.fdopen(tfd, 'w', 4096)

    # now run nttopt
    nttopt.main()

    # redirect stdout back to original
    sys.stdout.flush()
    sys.stdout = oldstdout

    return tfile


def run_pwsrepeat(infile):
    repeated = subprocess.check_output([pwsexec, infile, '2'])

    # rewrite outputs, find constants
    constmap = {}
    outlines = []
    outnums = []
    constre = re.compile("^P (V[0-9]+) = ([0-9]+) E$")
    outre = re.compile("^P O([0-9]+) = (.+) E$")
    for line in [ s.strip() for s in repeated.splitlines() ]:
        omatch = outre.match(line)
        if omatch is not None:
            # need to rewrite this
            newline = "P V" + omatch.group(1) + " = " + omatch.group(2) + " E"
            outnums.append(int(omatch.group(1)))
            outlines.append(newline)
            continue

        outlines.append(line)
        cmatch = constre.match(line)
        if cmatch is not None:
            # this is an input constant
            constmap[cmatch.group(2)] = cmatch.group(1)

    lout = len(outnums)//2
    assert 2 * lout == len(outnums), "Got an odd number of outputs! This should not happen."

    # multiply the results of the two NTTs
    firstnum = outnums[-1] + 1
    currnum = firstnum
    for (in1, in2) in zip(outnums[:lout], outnums[lout:]):
        outlines.append("P V" + str(currnum) + " = V" + str(in1) + " * V" + str(in2) + " E")
        currnum += 1

    return (outlines, constmap, firstnum, currnum)


def append_ntt(tfile, outlines, constmap, firstout, offset):
    inre = re.compile("^P V([0-9]+) = I[0-9]+ E$")
    vre = re.compile(" V([0-9]+) ")
    constre = re.compile(" ([0-9]+) ")
    with open(tfile, 'r') as f:
        for line in [ s.strip() for s in f ]:
            imatch = inre.match(line)
            if imatch is not None:
                assert firstout < offset, "Collision between input replacements and rewriting. This should not happen."
                newline = "P V" + str(int(imatch.group(1)) + offset) + " = V" + str(firstout) + " E"
                outlines.append(newline)
                firstout += 1
                continue

            # rewrite all V numbers
            # can't use finditer because we're rewriting the string as we go
            vmatch = vre.search(line)
            while vmatch is not None:
                line = line[:vmatch.start(1)] + str(int(vmatch.group(1)) + offset) + line[vmatch.end(1):]
                vmatch = vre.search(line, vmatch.end())

            # finally, rewrite any constants
            cmatch = constre.search(line)
            while cmatch is not None:
                const = cmatch.group(1)
                assert const in constmap, "Found new constant processing final NTT. This should not happen."
                line = line[:cmatch.start(1)] + constmap[const] + line[cmatch.end(1):]
                cmatch = constre.search(line)

            outlines.append(line)

    os.unlink(tfile)


def main():
    if len(sys.argv) != 2:
        print "usage:", sys.argv[0], "<logSize>"
        sys.exit(1)

    # get NTT PWS
    tfile = run_nttopt()

    # repeat it twice and post-process
    (outlines, constmap, firstout, offset) = run_pwsrepeat(tfile)

    # add final NTT step at the end
    append_ntt(tfile, outlines, constmap, firstout, offset)

    # print the result
    print "\n".join(outlines)


if __name__=="__main__":
    main()
