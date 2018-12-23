#!/usr/bin/python2.7

# generates a prover worksheet for a NTT with a power of two size.
# instead of taking all roots of unity (w^0, w^1, w^2, w^3,...) as
# inputs to the circuit, only powers of two are used (w^0, w^2,
# w^4,...), and these are multiplied together to obtain the rest.

import sys

logSize = 0
printLists = []
rootVarCt = 0
omega = 251207048322319823 # a 2^19th primitive root for the prime below.
prime = 2**63 + 2**19 + 1
def main():

    if (len(sys.argv) != 2):
        print "usage:", sys.argv[0], "<logSize>"
        return

    global logSize
    logSize = int(sys.argv[1])
    size = 2**logSize

    # make sure that the argument is OK
    if logSize > 19 or logSize < 1:
        print "ERROR: logSize must be between 1 and 19, inclusive."
        return

    # compute a primitive 2^logSize'th root of unity
    global omega
    omega = pow(omega, 2**(19 - logSize), prime)

    # the optimization: build up all the roots out of the powers of two.
    roots = printRoots(size)

    printInput(size)

    # The recursive fft is "depth-first", but we want to print out the
    # constraints layer by layer, so we buffer the constraints for
    # each layer in a list.
    global printLists
    printLists = [(i, []) for i in xrange(logSize)]

    # fft() fills in printLists
    fft(0, 0, size, 1, roots, 0)
    for i in xrange(logSize - 1, -1, -1):
        for j in xrange(len(printLists[i][1])):
            print printLists[i][1][j]

    printOutput(size, logSize * size + rootVarCt)

def fft(lOffset, rOffset, n, step, roots, depth):
    global printLists
    if (step < n):
        fft(rOffset,        lOffset,        n, step * 2, roots, depth + 1)
        fft(rOffset + step, lOffset + step, n, step * 2, roots, depth + 1)

        for i in xrange(0, n, 2* step):
            g = (logSize - depth - 1) * n + rootVarCt
            tmp = V(g + rOffset + i + step) + " ) * " +  "( " + toPow(roots[i]) + " )"

            p1 =   "P " + V( g + lOffset + n + i/2) + " = " + \
                V(g + rOffset + i) + " + ( " + tmp + " E"
            p2 =  "P " + V(g + lOffset + n + (i+n)/2) + " = " + \
                V(g + rOffset + i) + " minus ( " + tmp + " E"

            printLists[depth][1].append(p1)
            printLists[depth][1].append(p2)

def toPow(power):
    if (power[0] == 'V'):
        return power
    else:
        return str(pow(omega, int(power), prime))

def printRoots(size):
    inputRoots = [2**n for n in xrange(1, logSize)]
    currRoots = {}
    newRoots = {}
    for inputRoot in inputRoots:
        currRoots[inputRoot] = str(inputRoot)
    for numBits in xrange(logSize - 1):
         newRoots = printRootMult(currRoots, numBits + 2, size)
         currRoots = newRoots

    currRoots[0] = '1'
    return currRoots


def printRootMult(inputRoots, numBits, size):

    # We build up the powers of the root using the root raised to
    # powers of two, e.g. with numBits = 3, we multiply roots to
    # powers that have 1 and 2 nonzero bits to get powers that have 3
    # nonzero bits.
    # e.g. w^14 = w^{1110} = w^8 * w^6 = w^{1000} * w^{110}.

    newRoots = {}
    for i in xrange(0, size, 2):
        if bin(i).count('1') == numBits:
            l = bin(i)[2:]
            l = l.replace('1', '0', 1)
            r = bin(i)[2:]
            r = r[::-1].replace('1', '0', r.count('1') - 1)[::-1]
            #print l, r
            newRoots[i] = V(rootVarCt)
            p(inputRoots[int(l,2)], inputRoots[int(r,2)])

    mergedRoots = inputRoots.copy()
    mergedRoots.update(newRoots)
    return mergedRoots

def p(l, r):
    global rootVarCt
    print "P " + V(rootVarCt) + " = ( " + toPow(str(l)) + " ) * ( " + toPow(str(r)) + " ) E"
    rootVarCt += 1

def V(n):
    return "V" + str(n)

def printInput(n):
    for i in xrange(n):
        print "P " + V(i + rootVarCt) + " = " + "I" + str(i) + " E"

def printOutput(n, offset):
    for i in xrange(n):
        print "P O" + str(i) + " = " + V(i+ offset) + " E"



if __name__ == "__main__":
    main()



