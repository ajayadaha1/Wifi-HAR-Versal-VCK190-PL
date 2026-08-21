// Streaming live-demo host (robust): load once, reuse run objects, and replicate
// the PROVEN per-window sequence (graph.run(1) per window) that host.cpp uses,
// looping over a synthetic CSI recording. Emits pure feature lines for the
// dashboard: "mot0 mot1 mot2 <33 brt zeros> phs0 phs1 phs2".
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <unistd.h>
#include "xrt/xrt_device.h"
#include "xrt/xrt_kernel.h"
#include "xrt/xrt_bo.h"
#include "xrt/experimental/xrt_graph.h"

int main(int argc, char** argv) {
    const char* xclbin = (argc > 1) ? argv[1] : "inline_cogen_d1.xclbin";
    const char* rec    = (argc > 2) ? argv[2] : "demo_windows.txt";
    int period_ms      = (argc > 3) ? atoi(argv[3]) : 450;
    constexpr int N_IN = 256, N_OUT = 3;

    std::vector<std::vector<float>> windows;
    { std::ifstream f(rec); std::string line;
      while (std::getline(f, line)) {
        std::istringstream ss(line); std::vector<float> w; float x;
        while (ss >> x) w.push_back(x);
        if ((int)w.size() >= N_IN) { w.resize(N_IN); windows.push_back(w); }
      } }
    if (windows.empty()) { std::fprintf(stderr, "no windows in %s\n", rec); return 2; }
    std::fprintf(stderr, "demo: %zu windows loaded\n", windows.size());

    auto device = xrt::device(0);
    auto uuid   = device.load_xclbin(xclbin);
    auto mm2s   = xrt::kernel(device, uuid, "mm2s");
    auto s2mm   = xrt::kernel(device, uuid, "s2mm");
    auto in_bo  = xrt::bo(device, N_IN * sizeof(float),  mm2s.group_id(0));
    auto out_bo = xrt::bo(device, N_OUT * sizeof(float), s2mm.group_id(0));
    auto graph  = xrt::graph(device, uuid, "feature_graph");
    auto r_mm2s = xrt::run(mm2s);   // created once, restarted per window
    auto r_s2mm = xrt::run(s2mm);

    for (;;) {
      for (auto& w : windows) {
        in_bo.write(w.data());
        in_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);
        r_s2mm.set_arg(0, out_bo); r_s2mm.set_arg(2, N_OUT); r_s2mm.start();
        r_mm2s.set_arg(0, in_bo);  r_mm2s.set_arg(2, N_IN);  r_mm2s.start();
        graph.reset();
        graph.run(1);
        r_mm2s.wait(); r_s2mm.wait();
        out_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
        float o[N_OUT]; out_bo.read(o);
        char buf[96];
        std::snprintf(buf, sizeof buf, "%.6g %.6g %.6g", o[0], o[1], o[2]);
        std::string s = buf;
        for (int i = 0; i < 33; i++) s += " 0";
        s += " 0 0 0";
        std::printf("%s\n", s.c_str());
        std::fflush(stdout);
        usleep(period_ms * 1000);
      }
    }
}
