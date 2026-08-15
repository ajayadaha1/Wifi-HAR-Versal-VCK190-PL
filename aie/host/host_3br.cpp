// XRT host: validate the full 3-branch feature graph on VCK190.
//   motion:    input.txt(256)        -> FIR->stats   -> {mean,var,power}
//   breathing: breath_input.txt(64)  -> windowed-DFT -> 33 magnitude bins
//   phase-var: phase_input.txt(256)  -> stats         -> {mean,var,power}
// Feeds 3 mm2s CUs, drains 3 s2mm CUs; the PDI free-runs the graph (no graph.wait()).
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <string>
#include <vector>

#include "xrt/xrt_device.h"
#include "xrt/xrt_kernel.h"
#include "xrt/xrt_bo.h"
#include "xrt/experimental/xrt_graph.h"

static std::vector<float> load_floats(const char* path) {
    std::vector<float> v;
    std::ifstream f(path);
    for (float x; f >> x;) v.push_back(x);
    return v;
}

struct Branch { const char* name; int n_in; int n_out; const char* in_file; const char* gold_file; };

int main(int argc, char** argv) {
    const char* xclbin = (argc > 1) ? argv[1] : "feature_graph_3br.xclbin";
    const Branch B[3] = {
        {"mot", 256, 3,  "input.txt",        "golden.txt"},
        {"brt", 64,  33, "breath_input.txt", "breath_golden.txt"},
        {"phs", 256, 3,  "phase_input.txt",  "phase_golden.txt"},
    };

    auto device = xrt::device(0);
    auto uuid = device.load_xclbin(xclbin);

    std::vector<xrt::kernel> kmm(3), ksm(3);
    std::vector<xrt::bo> ibo(3), obo(3);
    std::vector<xrt::run> rmm(3), rsm(3);
    std::vector<std::vector<float>> gold(3);

    for (int i = 0; i < 3; i++) {
        kmm[i] = xrt::kernel(device, uuid, (std::string("mm2s_") + B[i].name).c_str());
        ksm[i] = xrt::kernel(device, uuid, (std::string("s2mm_") + B[i].name).c_str());
        auto in = load_floats(B[i].in_file);
        if (static_cast<int>(in.size()) < B[i].n_in) {
            std::printf("ERROR: %s needs %d samples, got %zu\n", B[i].in_file, B[i].n_in, in.size());
            return 2;
        }
        gold[i] = load_floats(B[i].gold_file);
        ibo[i] = xrt::bo(device, B[i].n_in * sizeof(float), kmm[i].group_id(0));
        obo[i] = xrt::bo(device, B[i].n_out * sizeof(float), ksm[i].group_id(0));
        ibo[i].write(in.data());
        ibo[i].sync(XCL_BO_SYNC_BO_TO_DEVICE);
    }

    auto graph = xrt::graph(device, uuid, "feature_graph");
    graph.reset();

    for (int i = 0; i < 3; i++) {                 // sinks first
        rsm[i] = xrt::run(ksm[i]);
        rsm[i].set_arg(0, obo[i]);
        rsm[i].set_arg(2, B[i].n_out);
        rsm[i].start();
    }
    for (int i = 0; i < 3; i++) {                 // then sources
        rmm[i] = xrt::run(kmm[i]);
        rmm[i].set_arg(0, ibo[i]);
        rmm[i].set_arg(2, B[i].n_in);
        rmm[i].start();
    }

    graph.run(1);

    for (int i = 0; i < 3; i++) rmm[i].wait();
    for (int i = 0; i < 3; i++) rsm[i].wait();     // no graph.wait() — PDI free-runs

    int rc = 0;
    for (int i = 0; i < 3; i++) {
        obo[i].sync(XCL_BO_SYNC_BO_FROM_DEVICE);
        std::vector<float> out(B[i].n_out);
        obo[i].read(out.data());
        int ng = std::min(static_cast<int>(gold[i].size()), B[i].n_out);
        float maxerr = 0.0f, maxg = 1e-12f;
        for (int j = 0; j < ng; j++) {
            maxerr = std::fmax(maxerr, std::fabs(out[j] - gold[i][j]));
            maxg = std::fmax(maxg, std::fabs(gold[i][j]));
        }
        bool pass = ng > 0 && (maxerr < 1e-3f || maxerr / maxg < 1e-4f);
        std::printf("[%s] n_out=%2d out[0]=%.6f gold[0]=%.6f max_abs_err=%.3e -> %s\n",
                    B[i].name, B[i].n_out, out[0], ng ? gold[i][0] : 0.0f, maxerr, pass ? "PASS" : "FAIL");
        if (!pass) rc = 1;
    }
    std::printf("OVERALL: %s\n", rc == 0 ? "PASS" : "FAIL");
    return rc;
}
