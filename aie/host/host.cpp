// XRT host app: validate the DDR -> AIE(FIR->stats) -> DDR datapath on VCK190.
//
// Streams N_IN fp32 samples from DDR through the feature graph via the mm2s PL
// data mover, drains N_OUT results ({mean, variance, power}) back through s2mm,
// and compares against the numpy golden (data/golden.txt). Runs on the A72 under
// PetaLinux; links against the target XRT in the platform sysroot (see Makefile).
#include <cmath>
#include <cstdio>
#include <fstream>
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

int main(int argc, char** argv) {
    const char* xclbin = (argc > 1) ? argv[1] : "feature_graph.xclbin";
    const char* in_path = (argc > 2) ? argv[2] : "input.txt";
    const char* gold_path = (argc > 3) ? argv[3] : "golden.txt";
    constexpr int N_IN = 256;   // BLOCK: FIR input length
    constexpr int N_OUT = 3;    // {mean, variance, power}

    std::vector<float> input = load_floats(in_path);
    if (static_cast<int>(input.size()) < N_IN) {
        std::printf("ERROR: need %d input samples, got %zu from %s\n", N_IN, input.size(), in_path);
        return 2;
    }
    std::vector<float> golden = load_floats(gold_path);

    auto device = xrt::device(0);
    auto uuid = device.load_xclbin(xclbin);

    auto mm2s = xrt::kernel(device, uuid, "mm2s");
    auto s2mm = xrt::kernel(device, uuid, "s2mm");

    auto in_bo = xrt::bo(device, N_IN * sizeof(float), mm2s.group_id(0));
    auto out_bo = xrt::bo(device, N_OUT * sizeof(float), s2mm.group_id(0));

    in_bo.write(input.data());
    in_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);

    auto graph = xrt::graph(device, uuid, "feature_graph");
    graph.reset();

    // Arg index 1 is the AXIS stream (platform-connected) and is not set here.
    auto r_s2mm = xrt::run(s2mm);          // start the sink before the graph produces
    r_s2mm.set_arg(0, out_bo);
    r_s2mm.set_arg(2, N_OUT);
    r_s2mm.start();

    auto r_mm2s = xrt::run(mm2s);
    r_mm2s.set_arg(0, in_bo);
    r_mm2s.set_arg(2, N_IN);
    r_mm2s.start();

    graph.run(1);

    r_mm2s.wait();
    // The packaged AIE CDO free-runs the graph, so graph.wait() never returns a
    // run-count completion; s2mm.wait() is the real (data-driven) barrier.
    r_s2mm.wait();

    out_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
    float out[N_OUT];
    out_bo.read(out);

    std::printf("AIE result: mean=%.6f var=%.6f power=%.6f\n", out[0], out[1], out[2]);
    if (static_cast<int>(golden.size()) >= N_OUT) {
        float maxerr = 0.0f;
        for (int i = 0; i < N_OUT; i++) maxerr = std::fmax(maxerr, std::fabs(out[i] - golden[i]));
        std::printf("golden:     mean=%.6f var=%.6f power=%.6f\n", golden[0], golden[1], golden[2]);
        std::printf("max_abs_err=%.3e -> %s\n", maxerr, (maxerr < 1e-3f) ? "PASS" : "FAIL");
        return (maxerr < 1e-3f) ? 0 : 1;
    }
    return 0;
}
