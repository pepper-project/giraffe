# libpws #

A library for interpreting PWS files

This code is ported from Zebra. I've traded the dependency on libchacha for
a dependency on libcrypto, rewritten the build system, and done other cleanup.

## Building ##

On debian-ish systems, you'll probably need the following:

    apt-get install build-essential g++-5 automake pkg-config \
                    python-dev libssl-dev libtool libtool-bin libgmp-dev

The above should translate straightforwardly to other package managers: you'll
need a C++11-compatible compiler (I've tested with g++ 5 and 6), automake,
pkg-config, libtool, and development headers for Python 2.7 and OpenSSL.

If you can't figure out what packages you need to install, please contact me!

## Contact ##

    rsw@cs.nyu.edu
