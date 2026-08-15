#include <adf.h>
#include <aie_api/aie.hpp>
#include "stats.h"
#include "stats_core.h"

void stats(adf::input_buffer<float> &in, adf::output_buffer<float> &out) {
    stats_core(in.data(), out.data());
}
