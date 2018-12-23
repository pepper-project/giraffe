// repeat PWS multiple times, but do not repeat constant gates
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// After parsing, a PWS file may have several inputs that take constants to be used
// in the circuit. When scaling a circuit horizontally, there is no point in repeating
// these constants. Moreover, this savings can be applied to layers beyond the input
// layer by noting that any gate with two constant inputs must have a constant output.
//
// This program takes in a PWS file and writes out a new PWS in which the original
// circuit is repeated multiple times, but the constants are not repeated.

#include <cstdlib>
#include <gmp.h>
#include <iostream>

#include "pws_circuit_parser.hh"
#include "math.hh"
#include "poly_utils.hh"
#include "util.h"

using namespace std;

typedef vector<map<int,int>> MuxSelsT;
typedef vector<pair<string,int>> InConstsT;
typedef map<int,unsigned> GateMapT;
typedef GateDescription::OpType GDOpTypeT;

static void printPWS(CircuitDescription &circuitDesc, MuxSelsT &mux_sel, InConstsT &inConsts, unsigned ncopies, unsigned nmuxsels, bool muxinc);
static unsigned inLookup(GateMapT &vars, GateMapT &consts, unsigned copy, unsigned nVars, int in);
static void showGate(GateDescription &gate, MuxSelsT &mux_sel, unsigned muxbase, unsigned vnum, unsigned in1, unsigned in2, char ovchar);
static void showPoly(unsigned vnum, unsigned in1, unsigned in2, GDOpTypeT op, char ovchar);
static void showMux(unsigned vnum, unsigned in1, unsigned in2, unsigned bitnum, char ovchar);
static const char *op2str(GDOpTypeT op);

int main (int argc, char **argv) {
    if (argc < 3) {
        cout << "Usage: " << argv[0] << " <foo.pws> <n> [-m]" << endl;
        cout << "-m: increment mux_sel bits when repeating (default behavior is copy)" << endl;
        return 1;
    }

    // #copies to make
    unsigned ncopies = 1;
    int nctmp = atoi(argv[2]);
    if (nctmp > 1) {
        ncopies = (unsigned) nctmp;
    } else {
        cout << "ERROR: Could not parse #copies, or #copies is 1. Aborting." << endl;
        return 1;
    }

    // are we incrementing or copying mux_sel bits?
    bool muxinc = false;
    if (argc > 3 && !strncmp("-m", argv[3], 2)) {
        muxinc = true;
    }

    // parse the circuit
    mpz_t prime;
    mpz_init_set_ui(prime, 1);
    mpz_mul_2exp(prime, prime, PRIMEBITS);
    mpz_sub_ui(prime, prime, PRIMEDELTA);
    PWSCircuitParser parser(prime);
    parser.optimize(argv[1]);
    if (parser.circuitDesc.size() == 0) {
        cout << "ERROR: failed to parse " << argv[1] << endl;
        exit(1);
    }

    unsigned nmuxsels = parser.largestMuxBitIndex + 1;
    printPWS(parser.circuitDesc, parser.muxGates, parser.inConstants, ncopies, nmuxsels, muxinc);
    return 0;
}

static void printPWS(CircuitDescription &circuitDesc, MuxSelsT &mux_sel, InConstsT &inConsts, unsigned ncopies, unsigned nmuxsels, bool muxinc) {
    map<int, unsigned> pvars;
    map<int, unsigned> vars;
    map<int, unsigned> pconsts;
    map<int, unsigned> consts;

    unsigned pnVars = 0;
    unsigned nVars = circuitDesc[0].size() - inConsts.size();
    // go through the consts and figure out their mapping first
    for (unsigned i = 0; i < inConsts.size(); i++) {
        consts[get<1>(inConsts[i])] = ncopies * nVars + i;
    }

    unsigned nConstsSoFar = 0;
    // now go through the vars and remap them to a numbering that does not include the consts
    for (unsigned i = 0; i < circuitDesc[0].size(); i++) {
        if (consts.count(i) != 0) {
            nConstsSoFar++;
        } else {
            vars[i] = i - nConstsSoFar;
        }
    }

    // dump the input layer
    for (unsigned j = 0; j < ncopies; j++) {
        for (unsigned i = 0; i < circuitDesc[0].size(); i++) {
            if (consts.count(i) == 0) {
                unsigned vnum = j*nVars + vars.at(i);
                cout << "P V" << vnum << " = I" << vnum << " E" << endl;
            }
        }
    }

    // now dump the constants
    for (unsigned i = 0; i < inConsts.size(); i++) {
        cout << "P V" << consts.at(get<1>(inConsts[i])) << " = " << get<0>(inConsts[i]) << " E" << endl;
    }

    // now remap and dump each layer
    unsigned prevbase = 0;
    unsigned gatebase = ncopies * nVars + inConsts.size();
    for (unsigned i = 1; i < circuitDesc.size(); i++) {
        LayerDescription &layer = circuitDesc[i];
        pvars.clear();
        pvars.swap(vars);
        pconsts.clear();
        pconsts.swap(consts);

        char ovchar = (i + 1 == circuitDesc.size()) ? 'O' : 'V';

        // figure out which outputs at this layer are purely constants
        nConstsSoFar = 0;
        for (unsigned j = 0; j < layer.size(); j++) {
            GateDescription &gate = layer[j];
            if (pconsts.count(gate.in1) != 0 && pconsts.count(gate.in2) != 0 && (gate.op != GateDescription::MUX || !muxinc)) {
                // both of this gate's inputs are constants
                // If this gate is a mux, we also require that we're not stepping the bit inputs
                //cout << "Found constant gate " << j << " (" << gate.in1 << ", " << gate.in2 << ")" << endl;
                consts[j] = nConstsSoFar;
                nConstsSoFar++;
            }
        }

        // the rest of these gates are non-constant
        pnVars = nVars;
        nVars = layer.size() - consts.size();

        // now pass over the gates and do the correct remapping
        nConstsSoFar = 0;
        for (unsigned j = 0; j < layer.size(); j++) {
            if (consts.count(j) != 0) {
                nConstsSoFar++;
                // this is a constant; now that we know nVars, update its value
                unsigned newval = consts.at(j) + ncopies * nVars;
                consts.at(j) = newval;
            } else {
                // this is a variable; remap it
                vars[j] = j - nConstsSoFar;
            }
        }

        // dump the variables for this layer
        for (unsigned j = 0; j < ncopies; j++) {
            for (unsigned k = 0; k < layer.size(); k++) {
                if (consts.count(k) == 0) {
                    GateDescription &gate = layer[k];
                    unsigned vnum = gatebase + j*nVars + vars.at(k);
                    unsigned in1 = prevbase + inLookup(pvars, pconsts, j, pnVars, gate.in1);
                    unsigned in2 = prevbase + inLookup(pvars, pconsts, j, pnVars, gate.in2);
                    unsigned muxbase = muxinc * j * nmuxsels;

                    showGate(gate, mux_sel, muxbase, vnum, in1, in2, ovchar);
                }
            }
        }

        // dump the constants for this layer
        for (unsigned j = 0; j < layer.size(); j++) {
            if (consts.count(j) != 0) {
                GateDescription &gate = layer[j];
                unsigned vnum = gatebase + consts.at(j);
                unsigned in1 = prevbase + pconsts.at(gate.in1);
                unsigned in2 = prevbase + pconsts.at(gate.in2);

                showGate(gate, mux_sel, 0, vnum, in1, in2, ovchar);
            }
        }

        prevbase = gatebase;
        gatebase += ncopies * nVars + consts.size();
    }
}

static unsigned inLookup(GateMapT &vars, GateMapT &consts, unsigned copy, unsigned nVars, int in) {
    if (consts.count(in) != 0) {
        return consts.at(in);
    } else {
        return vars.at(in) + copy * nVars;
    }
}

static void showGate(GateDescription &gate, MuxSelsT &mux_sel, unsigned muxbase, unsigned vnum, unsigned in1, unsigned in2, char ovchar) {
    if (gate.op != GateDescription::MUX) {
        showPoly(vnum, in1, in2, gate.op, ovchar);
    } else {
        unsigned mx = mux_sel[gate.pos.layer].at(gate.pos.name) + muxbase;
        showMux(vnum, in1, in2, mx, ovchar);
    }
}

static void showPoly(unsigned vnum, unsigned in1, unsigned in2, GDOpTypeT op, char ovchar) {
    cout << "P " << ovchar << vnum << " = V" << in1 << " " << op2str(op) << " V" << in2 << " E" << endl;
}

static void showMux(unsigned vnum, unsigned in1, unsigned in2, unsigned bitnum, char ovchar) {
    cout << "MUX " << ovchar << vnum << " = V" << in1 << " mux V" << in2 << " bit " << bitnum << endl;
}

static const char *op2str(GDOpTypeT op) {
    switch (op) {
        case GateDescription::ADD:
            return "+";
        case GateDescription::MUL:
            return "*";
        case GateDescription::SUB:
            return "minus";
        default:
            break;
    }

    cout << "ERROR: Got non-ADD, MUL, SUB, MUX gate. Aborting." << endl;
    exit(1);
}
