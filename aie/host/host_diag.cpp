// Diagnostic variant of host.cpp: prints (flushed) before/after every XRT step
// so the last line on the console pinpoints exactly which .wait() deadlocks.
#include <cmath>
#include <cstdio>
#include <fstream>
#include <vector>

#include "xrt/xrt_device.h"
#include "xrt/xrt_kernel.h"
#include "xrt/xrt_bo.h"
#include "xrt/experimental/xrt_graph.h"

#define STEP(msg) do { std::printf("[diag] " msg "\n"); std::fflush(stdout); } while (0)

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
    constexpr int N_IN = 256;
    constexpr int N_OUT = 3;

    std::vector<float> input = load_floats(in_path);
    if (static_cast<int>(input.size()) < N_IN) {
        std::printf("ERROR: need %d input samples, got %zu from %s\n", N_IN, input.size(), in_path);
        return 2;
    }
    std::vector<float> golden = load_floats(gold_path);

    STEP("open device");
    auto device = xrt::device(0);
    STEP("load_xclbin");
    auto uuid = device.load_xclbin(xclbin);

    STEP("create kernels mm2s/s2mm");
    auto mm2s = xrt::kernel(device, uuid, "mm2s");
    auto s2mm = xrt::kernel(device, uuid, "s2mm");

    auto in_bo = xrt::bo(device, N_IN * sizeof(float), mm2s.group_id(0));
    auto out_bo = xrt::bo(device, N_OUT * sizeof(float), s2mm.group_id(0));
    in_bo.write(input.data());
    in_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
    STEP("input bo synced to device");

    STEP("construct graph");
    auto graph = xrt::graph(device, uuid, "feature_graph");
    STEP("graph.reset()");
    graph.reset();

    auto r_s2mm = xrt::run(s2mm);
    r_s2mm.set_arg(0, out_bo);
    r_s2mm.set_arg(2, N_OUT);
    STEP("s2mm.start()");
    r_s2mm.start();

    auto r_mm2s = xrt::run(mm2s);
    r_mm2s.set_arg(0, in_bo);
    r_mm2s.set_arg(2, N_IN);
    STEP("mm2s.start()");
    r_mm2s.start();

    STEP("graph.run(1)");
    graph.run(1);

    STEP("WAIT mm2s ...");
    r_mm2s.wait();
    STEP("mm2s DONE");

    STEP("WAIT graph ...");
    graph.wait();
    STEP("graph DONE");

    STEP("WAIT s2mm ...");
    r_s2mm.wait();
    STEP("s2mm DONE");

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
