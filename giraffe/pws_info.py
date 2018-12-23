#!/usr/bin/python2.7

import os
import sys

sys.path.insert(1, os.path.abspath(os.path.join(os.path.dirname(__file__), 'pypws')))
import pypws

def main():
    if len(sys.argv) < 2:
        print "usage:", sys.argv[0], "<filename.pws>"
        sys.exit(1)
    elif not os.path.exists(sys.argv[1]):
        print "ERROR: cannot open", sys.argv[1]
        sys.exit(1)

    verbose = False
    if len(sys.argv) > 2:
        verbose = True

    pws_parsed = pypws.parse_pws(sys.argv[1])

    if verbose:
        print "# Info for", sys.argv[1]
        print "inputs:", len(pws_parsed[0])
    else:
        print len(pws_parsed[0])
        print len(pws_parsed[1:])

    totals = {'MUL':0, 'ADD':0, 'SUB':0, 'MUX':0}
    maxw = 0
    totw = 0
    for (num, lay) in enumerate(pws_parsed[1:]):
        oString = "layer %3d:" % (len(pws_parsed) - num - 2)
        counts = {'MUL': 0, 'ADD': 0, 'SUB': 0, 'MUX': 0}
        for (t, _, __, ___) in lay:
            counts[t] += 1
            totals[t] += 1

        if verbose:
            for t in sorted(counts.keys()):
                oString += "\t" + t + ": %5d" % counts[t]

            oString += "\t" + "Total: %5d" % len(lay)
            print oString

            if len(lay) > maxw:
                maxw = len(lay)
            totw += len(lay)
        else:
            print len(lay)

    if verbose:
        oString = "totals:    "
        for t in sorted(counts.keys()):
            oString += "\t" + t + ": %5d" % totals[t]

        oString += "\t" + "Total: %5d" % totw
        oString += "\t" + "Max: %5d" % maxw
        print oString
    else:
        print totals['MUL'], totals['ADD'], totals['SUB']

if __name__ == "__main__":
    main()
