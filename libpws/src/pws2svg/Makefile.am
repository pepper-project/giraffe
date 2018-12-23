AM_CPPFLAGS = -I$(srcdir)/../circuit $(OpenSSL_CFLAGS)
AM_CXXFLAGS = $(GLOBAL_CXXFLAGS) $(OPT_CXXFLAGS)

bin_PROGRAMS = pws2svg

pws2svg_SOURCES = pws2svg.cc pws2svg.hh
pws2svg_LDADD = ../circuit/libcircuit.la -lgmp $(OpenSSL_LIBS)
pws2svg_LDFLAGS = -static
# -static here just forces libcircuit to be linked statically.
# We can't use -all-static because lcrypto uses libdl.
