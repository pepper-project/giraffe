#pragma once

#include <gmp.h>
#include <memory>
#include <stdlib.h>
#include <stdint.h>

#include "utility.hh"

const size_t RANDOM_STATE_SIZE = 2048*mp_bits_per_limb/8;

class Prng {
    private:
        // need to use uniqe_ptr rather than array because
        // mp_bits_per_limb is not a constexpr.
        // Alternatively, we could just use a vector...
        std::unique_ptr<uint8_t[]> random_state;
        int random_index;

        void openssl_urandom(mpz_t m, const mpz_t n);
        void openssl_urandomb(mpz_t m, int nbits);
        void openssl_urandomb(char *buf, int nbits);
        void openssl_refill_randomness();

    public:
        Prng();
        void get_random(mpz_t m, const mpz_t n);
        template <typename T> void get_randomb(T m, int nbits);

        // Used when some random code needs a good prng.
        static Prng global;
};
