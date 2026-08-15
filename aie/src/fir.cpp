#include <adf.h>
#include <aie_api/aie.hpp>
#include "fir.h"
#include "fir_core.h"

void fir(adf::input_buffer<float> &in, adf::output_buffer<float> &out) {
    fir_core(in.data(), out.data());
}
