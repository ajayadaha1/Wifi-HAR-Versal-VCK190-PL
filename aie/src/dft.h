#pragma once
#include <adf.h>
#include "dftmat.h"

// N-point windowed DFT magnitude: N real samples in -> NB magnitude bins out.
void dft_mag(adf::input_buffer<float> &in, adf::output_buffer<float> &out);
