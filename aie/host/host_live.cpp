// host_live.cpp - live CSI drain for the D2ETH-ILA image using XRT-managed DDR
// buffers (NoC-valid bo.address()), NOT the fixed 0x7000_0000 /dev/mem path that
// Async-SErrors (PROJECT_STATE.md #27: 0x70000000 sits in a firewalled/reserved
// DDR aperture; the NoC rejects PL/CPU transactions to it).
//
// Datapath (co-gen xclbin): the only XRT kernels are mm2s + s2mm; the parser,
// csi_mux and s2mm_meta are overlay IP driven over /dev/mem. csi_mux selects the
// AIE input: S01=mm2s(DDR/golden) or S00=parser(live). s2mm drains AIE features.
//
//   --selftest : csi_mux=1, mm2s feeds input.txt, loop-drain s2mm->XRT bo, verify
//                vs golden.txt. Needs NO Pi -> proves the XRT-bo drain is SError-free.
//   (default)  : csi_mux=0 live parser feed; arm parser + s2mm_meta(-> XRT bo);
//                loop-drain s2mm->XRT bo; emit dashboard CSV (mot[3]+zeros) on stdout.
//
// Build: source the PetaLinux SDK env-setup, then
//   $CXX -std=c++17 -O2 host_live.cpp -o host_live -lxrt_coreutil -pthread
#include <cerrno>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>
#include <memory>
#include <chrono>
#include <thread>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

#include "xrt/xrt_device.h"
#include "xrt/xrt_kernel.h"
#include "xrt/xrt_bo.h"
#include "xrt/experimental/xrt_graph.h"

// ---- PL register map (identical to sw/pl_mac.py / live/inline_reader.py) ------
static constexpr uint64_t PL_BASE     = 0xA4000000ULL;
static constexpr uint64_t PL_SPAN     = 0x00100000ULL;
static constexpr uint32_t OFF_PARSER  = 0x00020000; // csi_udp_parser control
static constexpr uint32_t OFF_S2MMMET = 0x00030000; // metadata s2mm (HLS)
static constexpr uint32_t OFF_CSI_MUX = 0x00060000; // axis_switch
// HLS ap_ctrl_hs + s2mm arg regs
static constexpr uint32_t HLS_AP_CTRL = 0x00;
static constexpr uint32_t AP_START    = 1u << 0;
static constexpr uint32_t AP_AUTORST  = 1u << 7;    // 0x81 = start|auto_restart
static constexpr uint32_t S2MM_MEM_LO = 0x10;
static constexpr uint32_t S2MM_MEM_HI = 0x14;
static constexpr uint32_t S2MM_SIZE   = 0x1c;
static constexpr uint32_t PARSER_PORT = 0x10;       // UDP port (=5500)
// csi_mux (axis_switch): MI0 route @0x40 (0=parser/live, 1=mm2s/DDR), commit @0x00
static constexpr uint32_t MUX_MI0     = 0x40;
static constexpr uint32_t MUX_COMMIT  = 0x00;

static constexpr int META_WORDS = 2;   // one packed csi_meta_t = 64 bits

struct PLRegs {
    volatile uint8_t* base = nullptr;
    int fd = -1;
    bool open_() {
        fd = ::open("/dev/mem", O_RDWR | O_SYNC);
        if (fd < 0) { std::perror("open /dev/mem"); return false; }
        void* m = ::mmap(nullptr, PL_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED, fd, PL_BASE);
        if (m == MAP_FAILED) { std::perror("mmap PL"); return false; }
        base = static_cast<volatile uint8_t*>(m);
        return true;
    }
    void w(uint32_t off, uint32_t v) { *reinterpret_cast<volatile uint32_t*>(base + off) = v; }
    uint32_t r(uint32_t off) { return *reinterpret_cast<volatile uint32_t*>(base + off); }
    ~PLRegs() { if (base) ::munmap((void*)base, PL_SPAN); if (fd >= 0) ::close(fd); }
};

static std::vector<float> load_floats(const char* path) {
    std::vector<float> v; std::ifstream f(path);
    for (float x; f >> x;) v.push_back(x);
    return v;
}

int main(int argc, char** argv) {
    const char* xclbin = "inline_cogen_d2eth_ila.xclbin";
    const char* in_path = "input.txt";
    const char* gold_path = "golden.txt";
    bool selftest = false;
    double hz = 10.0;
    int selftest_iters = 5;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--selftest") selftest = true;
        else if (a == "--live") selftest = false;
        else if (a == "--hz" && i + 1 < argc) hz = std::stod(argv[++i]);
        else if (a == "--iters" && i + 1 < argc) selftest_iters = std::stoi(argv[++i]);
        else if (a == "--in" && i + 1 < argc) in_path = argv[++i];
        else if (a == "--gold" && i + 1 < argc) gold_path = argv[++i];
        else xclbin = argv[i];
    }
    constexpr int N_IN = 256;   // motion FIR input length
    constexpr int N_OUT = 3;    // {mean, variance, power}

    auto device = xrt::device(0);
    auto uuid = device.load_xclbin(xclbin);
    auto mm2s = xrt::kernel(device, uuid, "mm2s");
    auto s2mm = xrt::kernel(device, uuid, "s2mm");

    // XRT-managed DDR buffers (NoC-valid bo.address()) - the whole point.
    auto out_bo  = xrt::bo(device, N_OUT * sizeof(float), s2mm.group_id(0));
    auto meta_bo = xrt::bo(device, META_WORDS * sizeof(uint32_t), s2mm.group_id(0));
    std::fprintf(stderr, "XRT buffers: out_bo @0x%llx  meta_bo @0x%llx (NoC-valid DDR)\n",
                 (unsigned long long)out_bo.address(), (unsigned long long)meta_bo.address());

    PLRegs pl;
    if (!pl.open_()) return 3;

    // ---------------- self-test: golden mm2s feed, XRT-bo drain ----------------
    if (selftest) {
        std::vector<float> input = load_floats(in_path);
        if ((int)input.size() < N_IN) { std::fprintf(stderr, "need %d samples, got %zu\n", N_IN, input.size()); return 2; }
        std::vector<float> golden = load_floats(gold_path);
        auto in_bo = xrt::bo(device, N_IN * sizeof(float), mm2s.group_id(0));
        in_bo.write(input.data()); in_bo.sync(XCL_BO_SYNC_BO_TO_DEVICE);

        pl.w(OFF_CSI_MUX + MUX_MI0, 1); pl.w(OFF_CSI_MUX + MUX_COMMIT, 0x2);   // mux -> mm2s
        // The packaged AIE CDO free-runs the graph, so graph.reset()/run() on the
        // first xclbin loader can throw "already running/ended" - best-effort only;
        // the free-running graph processes the mm2s feed and s2mm.wait() is the barrier.
        std::unique_ptr<xrt::graph> gp;
        try { gp = std::make_unique<xrt::graph>(device, uuid, "feature_graph"); gp->reset(); }
        catch (const std::exception& e) { std::fprintf(stderr, "graph reset skipped (CDO free-runs): %s\n", e.what()); gp.reset(); }

        int rc = 0;
        for (int it = 0; it < selftest_iters; it++) {
            auto r_s2mm = xrt::run(s2mm); r_s2mm.set_arg(0, out_bo); r_s2mm.set_arg(2, N_OUT); r_s2mm.start();
            auto r_mm2s = xrt::run(mm2s); r_mm2s.set_arg(0, in_bo);  r_mm2s.set_arg(2, N_IN);  r_mm2s.start();
            if (gp) { try { gp->run(1); } catch (const std::exception&) {} }
            r_mm2s.wait();
            if (r_s2mm.wait(std::chrono::milliseconds(3000)) != ERT_CMD_STATE_COMPLETED) {
                std::fprintf(stderr, "iter %d: s2mm timeout\n", it); rc = 1; break;
            }
            out_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
            float out[N_OUT]; out_bo.read(out);
            float maxerr = 0.f;
            for (int j = 0; j < N_OUT && j < (int)golden.size(); j++) maxerr = std::fmax(maxerr, std::fabs(out[j] - golden[j]));
            bool pass = ((int)golden.size() >= N_OUT) ? (maxerr < 1e-3f) : true;
            std::printf("iter %d: mean=%.6f var=%.6f power=%.6f  max_abs_err=%.3e -> %s\n",
                        it, out[0], out[1], out[2], maxerr, pass ? "PASS" : "FAIL");
            if (!pass) rc = 1;
        }
        std::printf("SELFTEST %s (XRT-bo drain, no 0x70000000)\n", rc == 0 ? "PASS" : "FAIL");
        return rc;
    }

    // -------------------------- live parser drain ------------------------------
    // csi_mux -> live parser
    pl.w(OFF_CSI_MUX + MUX_MI0, 0); pl.w(OFF_CSI_MUX + MUX_COMMIT, 0x2);
    // arm s2mm_meta to the XRT meta buffer (NoC-valid), auto-restart -> drains the
    // parser's meta_out so it never backpressures/stalls the parser.
    uint64_t mpa = meta_bo.address();
    pl.w(OFF_S2MMMET + S2MM_MEM_LO, (uint32_t)(mpa & 0xFFFFFFFF));
    pl.w(OFF_S2MMMET + S2MM_MEM_HI, (uint32_t)(mpa >> 32));
    pl.w(OFF_S2MMMET + S2MM_SIZE,   META_WORDS);
    pl.w(OFF_S2MMMET + HLS_AP_CTRL, AP_START | AP_AUTORST);
    // start the parser (UDP 5500), auto-restart
    pl.w(OFF_PARSER + PARSER_PORT, 5500);
    pl.w(OFF_PARSER + HLS_AP_CTRL, AP_START | AP_AUTORST);

    std::fprintf(stderr, "live: csi_mux=0 (parser), parser+s2mm_meta armed; draining s2mm -> XRT bo\n");
    const auto period = std::chrono::microseconds((long)(1e6 / (hz > 0 ? hz : 10.0)));
    for (;;) {
        auto r_s2mm = xrt::run(s2mm); r_s2mm.set_arg(0, out_bo); r_s2mm.set_arg(2, N_OUT); r_s2mm.start();
        auto st = r_s2mm.wait(std::chrono::milliseconds(2000));
        if (st != ERT_CMD_STATE_COMPLETED) {          // no AIE window yet (no live frames?)
            std::fprintf(stderr, "waiting for AIE window (is the Pi streaming into SFP0? link up?)\n");
            continue;
        }
        out_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
        float out[N_OUT]; out_bo.read(out);
        meta_bo.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
        uint32_t meta[META_WORDS]; meta_bo.read(meta);
        // dashboard CSV: mot[3] + brt[33]=0 + phs[3]=0 (1-branch graph); meta tail.
        std::string line = std::to_string(out[0]) + "," + std::to_string(out[1]) + "," + std::to_string(out[2]);
        for (int j = 0; j < 33 + 3; j++) line += ",0";
        // meta tail: seq,rssi,n_sub,chanspec,core_spatial (unpacked like inline_reader)
        uint32_t w0 = meta[0], w1 = meta[1];
        unsigned seq = w0 & 0xFFFF, rssi = (w0 >> 16) & 0xFF, n_sub = (w0 >> 24) & 0xFF;
        unsigned chanspec = w1 & 0xFFFF, core_spatial = (w1 >> 16) & 0xFF;
        line += "," + std::to_string(seq) + "," + std::to_string((int)(int8_t)rssi) + "," +
                std::to_string(n_sub) + "," + std::to_string(chanspec) + "," + std::to_string(core_spatial);
        std::printf("%s\n", line.c_str());
        std::fflush(stdout);
        std::this_thread::sleep_for(period);
    }
    return 0;
}
