AM_CPPFLAGS = -I$(srcdir)/../circuit $(OpenSSL_CFLAGS)
AM_CXXFLAGS = $(GLOBAL_CXXFLAGS) $(OPT_CXXFLAGS)

bin_PROGRAMS = pws2sv

pws2sv_SOURCES = pws2sv.cc
pws2sv_LDADD = ../circuit/libcircuit.la -lgmp $(OpenSSL_LIBS)
pws2sv_LDFLAGS = -static
# -static here just forces libcircuit to be linked statically.
# We can't use -all-static because lcrypto uses libdl.
