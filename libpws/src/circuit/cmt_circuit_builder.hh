#pragma once

#include "cmt_circuit.hh"

class CMTCircuitBuilder
{
  public:
  virtual ~CMTCircuitBuilder();
  virtual CMTCircuit* buildCircuit() = 0;
  virtual void destroyCircuit(CMTCircuit* c);
};
