#include <adf.h>
#include <aie_api/aie.hpp>
#include "dft.h"
#include "dft_core.h"

// AIE wrapper around the shared pure-C DFT-magnitude core (dft_core.h).
void dft_mag(adf::input_buffer<float> &in, adf::output_buffer<float> &out) {
    dft_mag_core(in.data(), out.data());
}
