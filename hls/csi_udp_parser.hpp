#pragma once
// ---------------------------------------------------------------------------
// csi_udp_parser.hpp — inline nexmon_csi UDP parser for the VCK190 PL.
//
// Consumes an AXI4-Stream byte stream (one Ethernet frame per TLAST burst,
// as delivered by the AXI 1G/2.5G Ethernet Subsystem RX), filters IPv4/UDP to
// the CSI port, strips the nexmon header, and emits complex CSI samples on an
// AXI4-Stream plus one metadata record per frame.
//
// Wire-format constants MUST match csi_capture/decode_csi.py output. Assumes
// IPv4, no VLAN, IP IHL=5 (20 B), UDP, 18-byte nexmon header, and CSI stored
// as int16 little-endian I/Q pairs. FCS assumed stripped by the MAC.
// ---------------------------------------------------------------------------
#include <ap_int.h>
#include <ap_axi_sdata.h>
#include <hls_stream.h>

// Byte offsets within the Ethernet frame (IHL=5, no VLAN).
static const int ETH_HDR_BYTES = 14;
static const int IP_HDR_BYTES  = 20;
static const int UDP_HDR_BYTES = 8;
static const int NEX_HDR_BYTES = 18;
static const int CSI_OFFSET    = ETH_HDR_BYTES + IP_HDR_BYTES + UDP_HDR_BYTES + NEX_HDR_BYTES; // 60
static const int MAX_SUBCARRIERS = 256; // 80 MHz on bcm43455c0

typedef ap_axiu<8,  0, 0, 0> axis_byte; // RX byte stream from AXI-Ethernet
typedef ap_axiu<32, 0, 0, 0> axis_csi;  // packed { imag[31:16], real[15:0] }
typedef ap_axiu<64, 0, 0, 0> axis_meta; // one packed csi_meta_t per CSI frame

struct csi_meta_t {
    ap_uint<16> seq;          // nexmon sequence number
    ap_int<8>   rssi;         // dBm
    ap_uint<16> n_sub;        // subcarriers emitted this frame
    ap_uint<16> chanspec;     // channel/bandwidth spec
    ap_uint<8>  core_spatial; // core / spatial-stream byte
    ap_uint<1>  valid;        // 1 = a CSI frame was emitted
};

// --- metadata wire layout (64-bit AXIS TDATA, one beat per CSI frame) -------
// A beat is only emitted for a valid frame, so csi_meta_t::valid is implicit
// and is NOT carried on the wire. Keep this in sync with the DDR consumer.
//   [15:0] seq   [23:16] rssi   [39:24] n_sub   [55:40] chanspec
//   [63:56] core_spatial
static inline ap_uint<64> csi_meta_pack(const csi_meta_t &m) {
    ap_uint<64> w = 0;
    w(15, 0)  = m.seq;
    w(23, 16) = (ap_uint<8>)m.rssi;
    w(39, 24) = m.n_sub;
    w(55, 40) = m.chanspec;
    w(63, 56) = m.core_spatial;
    return w;
}

static inline csi_meta_t csi_meta_unpack(ap_uint<64> w) {
    csi_meta_t m;
    m.seq          = w(15, 0);
    m.rssi         = (ap_int<8>)(ap_uint<8>)w(23, 16);
    m.n_sub        = w(39, 24);
    m.chanspec     = w(55, 40);
    m.core_spatial = w(63, 56);
    m.valid        = 1;
    return m;
}

// Processes exactly one Ethernet frame per call (returns on TLAST).
void csi_udp_parser(hls::stream<axis_byte> &rx,
                    hls::stream<axis_csi>  &csi_out,
                    hls::stream<axis_meta> &meta_out,
                    ap_uint<16>             udp_port);
