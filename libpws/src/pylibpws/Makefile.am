AM_CPPFLAGS = -I$(srcdir)/../circuit $(OpenSSL_CFLAGS) $(PYTHON_INCLUDES)
AM_CXXFLAGS = $(GLOBAL_CXXFLAGS) $(OPT_CXXFLAGS)

pyexec_LTLIBRARIES = pylibpws.la

pylibpws_la_SOURCES = pylibpwsmodule.cc
pylibpws_la_LIBADD = ../circuit/libcircuit.la -lgmp $(OpenSSL_LIBS)
pylibpws_la_LDFLAGS = -module -avoid-version -export-symbols-regex initpylibpws -shared
