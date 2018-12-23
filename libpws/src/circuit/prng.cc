#include <openssl/rand.h>

#include "prng.hh"

using namespace std;

Prng Prng::global {};

Prng::Prng()
    : random_state (unique_ptr<uint8_t[]>(new uint8_t[RANDOM_STATE_SIZE]))
    , random_index (RANDOM_STATE_SIZE)
{
    openssl_refill_randomness();
}

void Prng::get_random(mpz_t m, const mpz_t n) {
    openssl_urandom(m, n);
}

template <typename T>
void Prng::get_randomb(T m, int nbits) {
    openssl_urandomb(m, nbits);
}

// force this specialization because we're linking separately
template
void Prng::get_randomb<char *>(char *, int);

// generates random number using openssl
void Prng::openssl_urandom(mpz_t m, const mpz_t n) {
    // figure out numbers of bits in n
    int nbits = int(mpz_sizeinbase(n, 2));

    // loop until m < n
    do {
        openssl_urandomb(m, nbits);
    } while (mpz_cmp(m, n) >= 0);
}

// generates random bits using one big call to openssl and keeping state
void Prng::openssl_urandomb(mpz_t m, int nbits) {

    // determine number of bytes
    int nbytes = ceil(double(nbits)/8.0);
    int diff = (nbytes <<3) - nbits;

    // check that we have enough randomness
    if ((RANDOM_STATE_SIZE-random_index) < nbytes) {
        openssl_refill_randomness();
    }

    // convert raw to mpz_t
    fast_mpz_import(m, random_state.get() + random_index, nbytes);

    // update index
    random_index += nbytes;

    // remove extra bits if needed
    if (diff != 0) {
        mpz_fdiv_q_2exp(m, m, diff);
    }
}

// generates random bits using one big call to openssl and keeping state
void Prng::openssl_urandomb(char *buf, int nbits) {
    if (nbits == 0)
        return;

    // determine number of bytes
    int nbytes = ceil(double(nbits)/8.0);
    int diff = (nbytes <<3) - nbits;

    // check that we have enough randomness
    if ((RANDOM_STATE_SIZE-random_index) < nbytes) {
        openssl_refill_randomness();
    }

    if (diff == 0) {
        memcpy(buf, random_state.get() + random_index, nbytes);
    } else {
        memcpy(buf, random_state.get() + random_index, nbytes - 1);
        char byte = random_state.get()[random_index + nbytes - 1];
        byte &= 0xFF >> (8 - diff);
        byte |= buf[nbytes - 1] & (0xFF << diff);
        buf[nbytes - 1] = byte;
    }

    // update index
    random_index += nbytes;
}

// generate new random state
void Prng::openssl_refill_randomness() {
    RAND_bytes(random_state.get(), random_index);
    random_index = 0;
}
