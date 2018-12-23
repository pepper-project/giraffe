#pragma once

#include <cassert>
#include <iostream>

#define assert_error(msg) assert(!(std::cerr << msg << std::endl))

template<typename T> bool
inRange(const T& val, const T& min, const T& max)
{
  return (val >= min) && (val < max);
}
