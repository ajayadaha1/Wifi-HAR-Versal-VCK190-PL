// ---------------------------------------------------------------------------
// csi_udp_parser_tb.cpp — C-sim testbench for csi_udp_parser.
//
// Default: builds a synthetic nexmon_csi Ethernet frame (N_SUB_TEST subcarriers,
// real=i, imag=-i) and checks the parser reproduces it exactly.
//
// Real-data mode: pass a .bin produced by
//   python3 ../csi_capture/decode_csi.py capture.pcap --dump-frame frame.bin
// as argv[1] to drive the parser with an actual captured frame.
// ---------------------------------------------------------------------------
#include "csi_udp_parser.hpp"
#include <cstdint>
#include <cstdio>
#include <vector>
#include <fstream>

#define CSI_UDP_PORT 5500
#define N_SUB_TEST   8

static void put_be16(std::vector<uint8_t> &v, uint16_t x) { v.push_back(x >> 8); v.push_back(x & 0xff); }
static void put_le16(std::vector<uint8_t> &v, uint16_t x) { v.push_back(x & 0xff); v.push_back(x >> 8); }

static std::vector<uint8_t> build_frame(int n_sub) {
    std::vector<uint8_t> f;
    for (int i = 0; i < 6; i++) f.push_back(0xff);          // dst MAC (broadcast)
    for (int i = 0; i < 6; i++) f.push_back(0x02);          // src MAC
    put_be16(f, 0x0800);                                    // ethertype IPv4
    // IPv4 header (IHL=5)
    f.push_back(0x45); f.push_back(0x00);
    put_be16(f, 0);                                         // total length (unused by parser)
    put_be16(f, 0); put_be16(f, 0);
    f.push_back(0x40); f.push_back(17);                     // ttl, proto=UDP
    put_be16(f, 0);                                         // checksum (unused)
    for (int i = 0; i < 4; i++) f.push_back(10);            // src IP
    for (int i = 0; i < 4; i++) f.push_back(20);            // dst IP
    // UDP header
    put_be16(f, 12345);                                     // src port
    put_be16(f, CSI_UDP_PORT);                              // dst port
    put_be16(f, 0); put_be16(f, 0);                         // length, checksum (unused)
    // nexmon header (18 bytes)
    put_le16(f, 0x1111);                                    // magic
    f.push_back(0xC0);                                      // rssi = -64
    f.push_back(0x08);                                      // frame control
    for (int i = 0; i < 6; i++) f.push_back(0xAA);          // src MAC
    put_le16(f, 0x1234);                                    // sequence number
    put_le16(f, 0x0001);                                    // core/spatial
    put_le16(f, 0xE02A);                                    // chanspec
    put_le16(f, 0x02D2);                                    // chip version
    // CSI: int16 LE real=i, imag=-i
    for (int i = 0; i < n_sub; i++) { put_le16(f, (uint16_t)(int16_t)i); put_le16(f, (uint16_t)(int16_t)(-i)); }
    return f;
}

static std::vector<uint8_t> load_bin(const char *path) {
    std::ifstream in(path, std::ios::binary);
    return std::vector<uint8_t>((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
}

int main(int argc, char **argv) {
    std::vector<uint8_t> frame = (argc > 1) ? load_bin(argv[1]) : build_frame(N_SUB_TEST);
    bool synthetic = (argc <= 1);
    if (frame.empty()) { printf("FAIL: empty input frame\n"); return 1; }

    hls::stream<axis_byte> rx;
    hls::stream<axis_csi>  csi_out;
    hls::stream<axis_meta> meta_out;

    for (size_t i = 0; i < frame.size(); i++) {
        axis_byte beat;
        beat.data = frame[i];
        beat.keep = 1; beat.strb = 1;
        beat.last = (i == frame.size() - 1) ? 1 : 0;
        rx.write(beat);
    }

    csi_udp_parser(rx, csi_out, meta_out, CSI_UDP_PORT);

    int n = 0, errors = 0;
    while (!csi_out.empty()) {
        axis_csi o = csi_out.read();
        int16_t re = (int16_t)(uint16_t)o.data(15, 0);
        int16_t im = (int16_t)(uint16_t)o.data(31, 16);
        if (synthetic && (re != n || im != -n)) {
            printf("  mismatch sub %d: got (%d,%d) expected (%d,%d)\n", n, re, im, n, -n);
            errors++;
        }
        n++;
    }

    if (meta_out.empty()) { printf("FAIL: no metadata emitted\n"); return 1; }
    axis_meta mw = meta_out.read();
    csi_meta_t m = csi_meta_unpack(mw.data);
    if (!mw.last) { printf("FAIL: metadata beat missing TLAST\n"); return 1; }
    printf("meta: valid=%d seq=0x%04x rssi=%d n_sub=%d chanspec=0x%04x\n",
           (int)m.valid, (unsigned)m.seq, (int)m.rssi, (int)m.n_sub, (unsigned)m.chanspec);
    printf("emitted %d CSI samples\n", n);

    if (synthetic) {
        if (n != N_SUB_TEST || errors || m.n_sub != N_SUB_TEST) { printf("TEST FAILED\n"); return 1; }
        printf("TEST PASSED\n");
    } else {
        printf("real-frame parse OK (verify n_sub matches decode_csi.py: %d)\n", n);
    }
    return 0;
}
