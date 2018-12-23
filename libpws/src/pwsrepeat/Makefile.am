AM_CPPFLAGS = -I$(srcdir)/../circuit $(OpenSSL_CFLAGS)
AM_CXXFLAGS = $(GLOBAL_CXXFLAGS) $(OPT_CXXFLAGS)

bin_PROGRAMS = pwsrepeat

pwsrepeat_SOURCES = pwsrepeat.cc
pwsrepeat_LDADD = ../circuit/libcircuit.la -lgmp $(OpenSSL_LIBS)
pwsrepeat_LDFLAGS = -static
# -static here just forces libcircuit to be linked statically.
# We can't use -all-static because lcrypto uses libdl.
