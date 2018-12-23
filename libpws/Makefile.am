ACLOCAL_AMFLAGS = -I m4

SUBDIRS = src
EXTRA_DIST = README.md autogen.sh
# old makefile is below
##   # libpws Makefile
##   
##   export CXX := g++
##   # aspirational cxxflags. no way code will build with them at this point...
##   #CXXFLAGS := -m64 -pedantic -pedantic-errors -std=c++11 -Werror -Wall -Wextra -Wshadow -Wpointer-arith -Wcast-qual -Wformat=2 -Weffc++
##   DEBUG ?= 0
##   ifeq ($(DEBUG),1)
##   CXXFLAGS += -Og -g
##   else
##   CXXFLAGS += -O2
##   endif
##   export CXXFLAGS += -m64 -pedantic -pedantic-errors -std=c++11 -fPIC
##   export IFLAGS += -I$(shell pwd)
##   export TOPLEVEL := 1
##   
##   LDLIBS := -lgmp -lcrypto -lrt
##   
##   .PHONY: ckts cktsclean all clean
##   all: ckts
##   
##   clean: cktsclean
##   
##   ckts:
##   	+make -C circuit
##   	+make -C util
##   
##   cktsclean:
##   	+make -C circuit clean
##   	+make -C util clean
