#pragma once
#include "dftmat.h"
#include <math.h>

// Pure-C windowed DFT magnitude (Hann + real DFT as matrix-vector), shared by
// the AIE kernel (dft.cpp) and the host test. |X[k]| for k in [0, N/2].
static inline void dft_mag_core(const float *x, float *mag) {
    for (int k = 0; k < NB; k++) {
        float re = 0.0f, im = 0.0f;
        for (int nn = 0; nn < N; nn++) {
            float xw = x[nn] * HANN[nn];
            re += xw * COSM[k * N + nn];
            im -= xw * SINM[k * N + nn];
        }
        mag[k] = sqrtf(re * re + im * im);
    }
}
