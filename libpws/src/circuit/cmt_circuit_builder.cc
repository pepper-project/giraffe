#include "cmt_circuit_builder.hh"

CMTCircuitBuilder::
~CMTCircuitBuilder()
{ }

void CMTCircuitBuilder::
destroyCircuit(CMTCircuit* c)
{
  delete c;
}

