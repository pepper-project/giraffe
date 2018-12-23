#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# test circuit prover

# hack: this test lives in a subdir
import sys
import os.path
sys.path.insert(1, os.path.abspath(os.path.join(sys.path[0], os.pardir)))

import random

from giraffelib import util, randutil
from giraffelib.arithcircuit import ArithCircuit, ArithCircuitLayer, ArithCircuitInputLayer
from giraffelib.circuitprover import _DummyCircuitProver
from giraffelib.defs import Defs
from giraffelib.layercompute import LayerComputeBeta
from giraffelib.layerprover import InputLayer, LayerProver

def run_one_test(nInBits, nCopies):
    nOutBits = nInBits

    circuit = _DummyCircuitProver(nCopies)
    inLayer = InputLayer(nOutBits)

    (in0v, in1v, typv) = randutil.rand_ckt(nOutBits, nInBits)
    typc = [ tc.cgate for tc in typv ]
    inputs = randutil.rand_inputs(nInBits, nCopies)

    # compute outputs
    ckt = ArithCircuit()
    inCktLayer = ArithCircuitInputLayer(ckt, nOutBits)
    outCktLayer = ArithCircuitLayer(ckt, inCktLayer, in0v, in1v, typc)
    ckt.layers = [inCktLayer, outCktLayer]
    outputs = []
    for inp in inputs:
        ckt.run(inp)
        outputs.append(ckt.outputs)

    z1 = [Defs.gen_random() for _ in range(0, nOutBits)]
    z2 = [Defs.gen_random() for _ in range(0, circuit.nCopyBits)]

    outLayer = LayerProver(inLayer, circuit, in0v, in1v, typv)
    outLayer.set_inputs(inputs)
    outLayer.set_z(z1, z2)

    # mlExt of outputs
    outflat = util.flatten(outputs)
    inLayer_mults = LayerComputeBeta(nOutBits + outLayer.circuit.nCopyBits, z1 + z2)
    assert len(outflat) == len(inLayer_mults.outputs)
    inLayermul = util.mul_vecs(inLayer_mults.outputs, outflat)
    inLayerExt = sum(inLayermul) % Defs.prime

    w3 = [ Defs.gen_random() for _ in range(0, circuit.nCopyBits) ]
    w1 = [ Defs.gen_random() for _ in range(0, nInBits) ]
    w2 = [ Defs.gen_random() for _ in range(0, nInBits) ]

    outLayer.compute_outputs()
    initOutputs = outLayer.output

    assert inLayerExt == (initOutputs[0] + sum(initOutputs)) % Defs.prime

    for i in range(0, len(w3)):
        outLayer.next_round(w3[i])
        outLayer.compute_outputs()

    for i in range(0, len(w1)):
        outLayer.next_round(w1[i])
        outLayer.compute_outputs()

    for i in range(0, len(w2)):
        outLayer.next_round(w2[i])
        outLayer.compute_outputs()

    finalOutputs = outLayer.output

    # check the outputs by computing mlext of layer input directly

    inflat = util.flatten(inputs)

    v1_mults = LayerComputeBeta(outLayer.prevL.nOutBits + outLayer.circuit.nCopyBits, w1 + w3)
    assert len(inflat) == len(v1_mults.outputs)
    v1inmul = util.mul_vecs(v1_mults.outputs, inflat)
    v1 = sum(v1inmul) % Defs.prime

    v2_mults = LayerComputeBeta(outLayer.prevL.nOutBits + outLayer.circuit.nCopyBits, w2 + w3)
    assert len(inflat) == len(v2_mults.outputs)
    v2inmul = util.mul_vecs(v2_mults.outputs, inflat)
    v2 = sum(v2inmul) % Defs.prime

    assert v1 == finalOutputs[0]
    assert v2 == sum(finalOutputs) % Defs.prime

def run_tests(num_tests):
    for _ in range(0, num_tests):
        run_one_test(random.randint(2, 6), 2**random.randint(1, 6))
        sys.stdout.write('.')
        sys.stdout.flush()

    print " (layer test passed)"

if __name__ == "__main__":
    run_tests(128)
