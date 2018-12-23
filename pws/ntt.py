#!/usr/bin/python2.7

import sys

logSize = 0
printLists = []

def V(n):
    return "V" + str(n)

def fft(lOffset, rOffset, n, step, roots, depth):
    global printLists
    global logSize
    if (step < n):
        fft(rOffset,        lOffset,        n, step * 2, roots, depth + 1)
        fft(rOffset + step, lOffset + step, n, step * 2, roots, depth + 1)

        for i in xrange(0, n, 2* step):
            g = (logSize - depth - 1) * n
            tmp = V(g + rOffset + i + step) + " ) * " +  "( " + roots[i] + " )"

            p1 =   "P " + V( g + lOffset + n + i/2) + " = " + \
                V(g + rOffset + i) + " + ( " + tmp + " E"
            p2 =  "P " + V(g + lOffset + n + (i+n)/2) + " = " + \
                V(g + rOffset + i) + " minus ( " + tmp + " E"

            printLists[depth][1].append(p1)
            printLists[depth][1].append(p2)

def constants(n):
    if (n == 0):
        return "1"
    if (n % 2 == 1):
        return "0"
    else:
        return str(n)


def main():

    if (len(sys.argv) != 2):
        print "usage:", sys.argv[0], "<logSize>"
        return

    global logSize
    logSize = int(sys.argv[1])
    size = 2**logSize

    global printLists

    printLists = [(i, []) for i in xrange(logSize)]

    printInput(size)
    roots = [constants(n) for n in xrange(size)]

    fft(0, 0, size, 1, roots, 0)

    for i in xrange(logSize - 1, -1, -1):
        for j in xrange(len(printLists[i][1])):
            print printLists[i][1][j]

    printOutput(size, logSize * size)

def printInput(n):
    for i in xrange(n):
        print "P " + V(i) + " = " + "I" + str(i) + " E"

def printOutput(n, offset):
    for i in xrange(n):
        print "P O" + str(i) + " = " + V(i+ offset) + " E"


if __name__ == "__main__":
    main()



