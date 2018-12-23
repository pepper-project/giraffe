AM_CPPFLAGS = -I$(srcdir)/../circuit $(OpenSSL_CFLAGS)
AM_CXXFLAGS = $(GLOBAL_CXXFLAGS) $(OPT_CXXFLAGS)

GLOBAL_LDADD = ../circuit/libcircuit.la -lgmp $(OpenSSL_LIBS)

check_PROGRAMS = pws_circuit_test

pws_circuit_test_SOURCES = pws_circuit_test.cc
pws_circuit_test_LDADD = $(GLOBAL_LDADD)

dist_check_SCRIPTS = simple4.test pws2sv.test pws2svg.test

TESTS = simple4.test pws2sv.test pws2svg.test
