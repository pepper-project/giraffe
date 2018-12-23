// parse PWS into localparam definitions
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

#include <cstdlib>
#include <gmp.h>
#include <iostream>

#include "pws_circuit_parser.hh"
#include "math.hh"
#include "poly_utils.hh"
#include "util.h"

using namespace std;

typedef vector<map<int,int>> MuxSelT;

static void printVerilogDefs(CircuitDescription &circuitDesc, MuxSelT &mux_sel, unsigned nmuxsels);
static void printVerilogInParam(unsigned ngates, unsigned ninbits, unsigned lnum, const char *name, vector<unsigned> &in);

int main(int argc, char **argv) {
    if (argc < 2) {
        cout << "Usage: " << argv[0] << " <foo.pws>" << endl;
        return 1;
    }

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
    printVerilogDefs(parser.circuitDesc, parser.muxGates, nmuxsels);
    return 0;
}

static void printVerilogDefs(CircuitDescription &circuitDesc, MuxSelT &mux_sel, unsigned nmuxsels) {
    unsigned nlayers, ninputs, ngates, ninbits, nmuxbits;
    vector<string> fn;
    vector<unsigned> in0;
    vector<unsigned> in1;
    vector<unsigned> mx;

    nlayers = circuitDesc.size() - 1;
    nmuxbits = log2i(nmuxsels);
    nmuxbits = nmuxbits ? nmuxbits : 1;
    cout << "localparam nlayers = " << nlayers << ";" << endl;
    cout << "localparam nmuxsels = " << nmuxsels << ";" << endl;

    // ngates in layer 0 is the number of inputs to the circuit
    ngates = circuitDesc[0].size();

    for (unsigned i = 1; i < circuitDesc.size(); i++) {
        LayerDescription &layer = circuitDesc[i];
        fn.clear();
        in0.clear();
        in1.clear();
        mx.clear();
        fn.reserve(layer.size());
        in0.reserve(layer.size());
        in1.reserve(layer.size());
        mx.reserve(layer.size());

        ninputs = ngates;
        ngates = layer.size();

        for (unsigned j = 0; j < layer.size(); j++) {
            GateDescription &gate = layer[j];
            if (gate.op == GateDescription::DIV_INT || gate.op == GateDescription::CONSTANT) {
                // error: circuit must have only add and mul
                cerr << "ERROR: DIV_INT or CONSTANT gate encountered; aborting." << endl;
                exit(-1);
            } else {
                fn.push_back(gate.strOpType());
                in0.push_back(gate.in1);
                in1.push_back(gate.in2);
                if (gate.op == GateDescription::MUX) {
                    mx.push_back(mux_sel[gate.pos.layer].at(gate.pos.name));
                } else {
                    mx.push_back(0);
                }
            }
        }

        unsigned lnum = nlayers - i;
        ninbits = log2i(ninputs); // $clog2(ninputs) in verilogese ; defined in math.h
        // now dump out the params for this layer of the circuit
        cout << '\0';
        cout << "localparam ngates_" << lnum << " = " << ngates << ";" << endl;
        cout << "localparam ninputs_" << lnum << " = " << ninputs << ";" << endl;

        cout << "localparam [`GATEFN_BITS*" << ngates << "-1:0] gates_fn_" << lnum << " = {";
        for (int j = (int) fn.size() - 1; j >= 0; j--) {
            cout << "`GATEFN_" << fn[j];
            if (j != 0) {
                cout << ", ";
            }
        }
        cout << "};" << endl;

        printVerilogInParam(ngates, ninbits, lnum, "in0", in0);
        printVerilogInParam(ngates, ninbits, lnum, "in1", in1);
        printVerilogInParam(ngates, nmuxbits, lnum, "mux", mx);
    }
}

static void printVerilogInParam(unsigned ngates, unsigned ninbits, unsigned lnum, const char *name, vector<unsigned> &in) {
    cout << "localparam [" << ngates * ninbits - 1 << ":0] gates_" << name << "_" << lnum << " = {";
    for (int j = (int) in.size() - 1; j >= 0; j--) {
        cout << ninbits << "'h" << hex << in[j] << dec;
        if (j != 0) {
            cout << ", ";
        }
    }
    cout << "};" << endl;
}
