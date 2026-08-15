#pragma once
#include "params.h"

// Pure-C two-pass stats (mean, population variance, power) over one buffer.
static inline void stats_core(const float *x, float *out) {
    float s = 0.0f;
    for (int i = 0; i < L; i++) s += x[i];
    float mean = s / (float)L;

    float sd = 0.0f, s2 = 0.0f;
    for (int i = 0; i < L; i++) {
        float d = x[i] - mean;
        sd += d * d;
        s2 += x[i] * x[i];
    }
    out[0] = mean;
    out[1] = sd / (float)L;
    out[2] = s2 / (float)L;
}
