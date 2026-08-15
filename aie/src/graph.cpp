#pragma once
#include <adf.h>
#include "fir.h"
#include "stats.h"
#include "dft.h"
using namespace adf;

// Three-branch CSI feature graph on the AIE array (toward the 8-feature vector):
//   motion:    PLIO_in(BLOCK)     -> FIR band-pass -> stats -> PLIO_out {mean,var,power}
//   breathing: PLIO_brt_in(N)     -> windowed-DFT magnitude -> PLIO_brt_out (NB bins)
//   phase-var: PLIO_phase_in(L)   -> stats -> PLIO_phase_out {mean, variance(=phase-var), power}
class FeatureGraph : public graph {
public:
    kernel kfir, kstats, kdft, kphase;
    input_plio in, brt_in, phase_in;
    output_plio out, brt_out, phase_out;

    FeatureGraph() {
        kfir = kernel::create(fir);
        kstats = kernel::create(stats);
        kdft = kernel::create(dft_mag);
        kphase = kernel::create(stats);
        in = input_plio::create("PLIO_in", plio_32_bits, "data/input.txt");
        out = output_plio::create("PLIO_out", plio_32_bits, "data/output.txt");
        brt_in = input_plio::create("PLIO_brt_in", plio_32_bits, "data/breath_input.txt");
        brt_out = output_plio::create("PLIO_brt_out", plio_32_bits, "data/breath_output.txt");
        phase_in = input_plio::create("PLIO_phase_in", plio_32_bits, "data/phase_input.txt");
        phase_out = output_plio::create("PLIO_phase_out", plio_32_bits, "data/phase_output.txt");

        // motion branch: FIR band-pass -> stats (kernel-to-kernel)
        connect<>(in.out[0], kfir.in[0]);
        connect<>(kfir.out[0], kstats.in[0]);
        connect<>(kstats.out[0], out.in[0]);
        // breathing branch: windowed-DFT magnitude
        connect<>(brt_in.out[0], kdft.in[0]);
        connect<>(kdft.out[0], brt_out.in[0]);
        // phase-variance branch: stats -> variance is the phase-var feature
        connect<>(phase_in.out[0], kphase.in[0]);
        connect<>(kphase.out[0], phase_out.in[0]);

        dimensions(kfir.in[0]) = {BLOCK};
        dimensions(kfir.out[0]) = {BLOCK};
        dimensions(kstats.in[0]) = {L};
        dimensions(kstats.out[0]) = {NOUT};
        dimensions(kdft.in[0]) = {N};
        dimensions(kdft.out[0]) = {NB};
        dimensions(kphase.in[0]) = {L};
        dimensions(kphase.out[0]) = {NOUT};

        source(kfir) = "fir.cpp";
        source(kstats) = "stats.cpp";
        source(kdft) = "dft.cpp";
        source(kphase) = "stats.cpp";
        runtime<ratio>(kfir) = 0.5;
        runtime<ratio>(kstats) = 0.5;
        runtime<ratio>(kdft) = 0.5;
        runtime<ratio>(kphase) = 0.5;
    }
};

FeatureGraph feature_graph;

#if defined(__X86SIM__) || defined(__AIESIM__)
int main(void) {
    feature_graph.init();
    feature_graph.run(1);
    feature_graph.end();
    return 0;
}
#endif
