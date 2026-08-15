#pragma once
#include "coeffs.h"

// Pure-C block FIR (shared by AIE kernel + host), causal with zero-pad history.
static inline void fir_core(const float *x, float *y) {
    for (int n = 0; n < BLOCK; n++) {
        float acc = 0.0f;
        for (int k = 0; k < N_TAPS; k++) {
            int i = n - k;
            acc += (i >= 0) ? COEFFS[k] * x[i] : 0.0f;
        }
        y[n] = acc;
    }
}
