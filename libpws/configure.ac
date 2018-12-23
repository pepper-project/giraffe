#                                               -*- Autoconf -*-
# Process this file with ./autogen.sh to produce a configure script

AC_PREREQ([2.68])
AC_INIT([libpws], [0.01], [rsw@cs.nyu.edu])
AM_INIT_AUTOMAKE([foreign])
AC_CONFIG_SRCDIR([src/circuit/tokenizer.hh])
AC_CONFIG_HEADERS([config.h])
AC_CONFIG_MACRO_DIRS([m4])

# Add C++ flags
#PICKY_CXXFLAGS="-Wall -Wpedantic -Wextra -Weffc++ -Werror"
#PICKIER_CXXFLAGS="-Werror -Wall -Wextra -Wshadow -Wpointer-arith -Wcast-qual -Wformat=2 -Weffc++"
GLOBAL_CXXFLAGS="-m64 -std=c++11 -pedantic -pedantic-errors -Wpedantic -Werror"
AC_SUBST([GLOBAL_CXXFLAGS])

AC_ARG_ENABLE([debug],
  [AS_HELP_STRING([--enable-debug], [Enable -Og -g flags])],
  [case "$enableval" in
     no)
       OPT_CXXFLAGS="-O2"
       ;;
     '' | yes)
       OPT_CXXFLAGS="-Og -g"
       ;;
     *)
       AC_MSG_ERROR([Unknown argument '$enableval' to --enable-debug])
       ;;
   esac],
  [OPT_CXXFLAGS="-O2"])
AC_SUBST(OPT_CXXFLAGS)

# Checks for programs.
AC_PROG_CXX
LT_INIT

# Checks for libraries.
PKG_CHECK_MODULES([OpenSSL], [libcrypto])
AC_CHECK_LIB(gmp, __gmpz_powm_sec, , [AC_MSG_ERROR([GnuMP >= 5 not found. You need libgmp-dev or equivalent.])])

# Checks for header files.

# Checks for typedefs, structures, and compiler characteristics.

# Checks for library functions.

# Check for Python
AM_PATH_PYTHON(2.7)
AM_CHECK_PYTHON_HEADERS(,[AC_MSG_ERROR(could not find Python headers)])

AC_CONFIG_FILES([Makefile src/Makefile src/circuit/Makefile src/pws2sv/Makefile src/pwsrepeat/Makefile src/pws2svg/Makefile src/pylibpws/Makefile src/tests/Makefile])

AC_OUTPUT
