#include <gmp.h>
#include <iostream>

#include "math.hh"
#include "poly_utils.hh"
#include "pws_circuit_parser.hh"
#include "pws_circuit.hh"

using namespace std;

int main(int argc, char **argv) {
    if (argc > 1)  {
        mpz_t prime;
        mpz_init(prime);
        mpz_set_ui(prime, 2305843009213693951);
        PWSCircuitParser parser(prime);
        PWSCircuit c(parser);

        cout << "==== Constructing Circuit ====" << endl;
        parser.parse(argv[1]);
        cout << "==== Construction Complete ====" << endl;

        cout << "Constructing circuit" << endl;
        c.construct();
        MPQVector vec(c.getInputSize());
        for (size_t i = 0; i < vec.size(); i++)
            mpq_set_ui(vec[i], i, 1);

        parser.printCircuitDescription();
        //c.print();

        cout << "init input" << endl;
        c.initializeInputs(vec);

        cout << "evaluate" << endl;
        c.evaluate();

        //exit(1);
        c.print();

        cout << "computeChiall test" << endl;
    

        int outputSize = 8;
        int logOutputSize = log2i(outputSize);
        int inputSize = 4;
        int logInputSize = log2i(inputSize);

        int randLength = logOutputSize + 2 * logInputSize;
        MPZVector rand(randLength);
        
        for (int i = 0; i < randLength; i++) {
            mpz_set_si(rand[i], i+2);
        }

        MPZVector w0Chi(outputSize);
        MPZVector w1Chi(inputSize);
        MPZVector w2Chi(inputSize);

        MPZVector w0R(logOutputSize);
        MPZVector w12R(logInputSize);

        w0R.copy(rand, 0, logOutputSize);


        for (int i = 0; i < logOutputSize; i++) {
            gmp_printf("w0R[%d]: %Zd\n", i, w0R[i]);
        }

        computeChiAll(w0Chi,  w0R,  prime);
    
        w12R.copy(rand, logOutputSize, logInputSize);
        computeChiAll(w1Chi, w12R, prime);

        w12R.copy(rand, logOutputSize + logInputSize, logInputSize);
        computeChiAll(w2Chi, w12R, prime);


        for (int i = 0; i < outputSize; i++) {
            gmp_printf("w0Chi[%d]: %Zd\n", i, w0Chi[i]);
        }


    }
    else  {
        cout << "ERROR: Requires pws file." << endl;
    }
}

