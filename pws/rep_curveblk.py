#!/usr/bin/env python2.7
# Generates double-and-add blocks for c25519.
# Note that the mux bit is the same for blocks which are in parallel.

# Also note: mux bit 0 is actually (key bit 0) xor (key bit 1), mux
# bit 2 is (key bit 1) xor (key bit 2), etc.

import sys

def main():

    if (len(sys.argv) != 3):
        print "usage:", sys.argv[0], "<depth> <width>"
        return

    depth = int(sys.argv[1])
    width = int(sys.argv[2])

    offset = 0
    for i in xrange(width):
        print genInputLines(offset)

        for j in xrange(depth):
            print block(offset, j)
            offset += 22

        print genOutputLines(offset)
        offset += 4

def block(offset, bitCt):
    V = [i + offset - 4 for i in xrange(30)]
    repLines = """
P V{8} = V{4} + V{5} E
P V{9} = V{4} minus V{5} E
P V{10} = V{6} + V{7} E
P V{11} = V{6} minus V{7} E

P V{12} = V{8} * V{8} E
P V{13} = V{9} * V{9} E
P V{14} = V{9} * V{10} E
P V{15} = V{8} * V{11} E

P V{16} = V{12} * V{13} E
P V{17} = V{12} minus V{13} E
P V{18} = V{14} + V{15} E
P V{19} = V{14} minus V{15} E

P V{20} = V{17} * 121665 E
P V{21} = V{18} * V{18} E
P V{22} = V{19} * V{19} E

P V{23} = V{12} + V{20} E
P V{24} = V{22} * V0 E

P V{25} = V{17} * V{23} E

MUX V{26} = V{16} mux V{21} bit {b0}
MUX V{27} = V{25} mux V{24} bit {b0}
MUX V{28} = V{21} mux V{16} bit {b0}
MUX V{29} = V{24} mux V{25} bit {b0}
""".format(V[0], V[1], V[2], V[3], V[4], V[5], V[6], V[7],         \
           V[8], V[9], V[10], V[11], V[12], V[13], V[14], V[15],   \
           V[16], V[17], V[18], V[19], V[20], V[21], V[22], V[23], \
           V[24], V[25], V[26], V[27], V[28], V[29], b0= bitCt)

    return repLines

def genInputLines(offset):
    V = [i + offset for i in xrange(4)]
    inputLines = """
P V{0} = I{0} E
P V{1} = I{1} E
P V{2} = I{2} E
P V{3} = I{3} E
""".format(V[0], V[1], V[2], V[3])

    return inputLines

def genOutputLines(offset):
    V = [i + offset for i in xrange(4)]
    outputLines = """
P O{0} = V{0} E
P O{1} = V{1} E
P O{2} = V{2} E
P O{3} = V{3} E
""".format(V[0], V[1], V[2], V[3])

    return outputLines

if __name__ == "__main__":
    main()

