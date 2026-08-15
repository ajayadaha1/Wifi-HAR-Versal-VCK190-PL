// ---------------------------------------------------------------------------
// csi_udp_parser.cpp — see csi_udp_parser.hpp for the wire-format contract.
// ---------------------------------------------------------------------------
#include "csi_udp_parser.hpp"

void csi_udp_parser(hls::stream<axis_byte>  &rx,
                    hls::stream<axis_csi>   &csi_out,
                    hls::stream<csi_meta_t> &meta_out,
                    ap_uint<16>              udp_port) {
#pragma HLS INTERFACE axis port=rx
#pragma HLS INTERFACE axis port=csi_out
#pragma HLS INTERFACE ap_fifo port=meta_out
#pragma HLS INTERFACE s_axilite port=udp_port bundle=ctrl
#pragma HLS INTERFACE s_axilite port=return   bundle=ctrl

    ap_uint<16> ethertype = 0;
    ap_uint<8>  ip_proto  = 0;
    ap_uint<16> dport     = 0;
    bool        keep      = true;   // set false as soon as a filter fails

    csi_meta_t meta;
    meta.seq = 0; meta.rssi = 0; meta.n_sub = 0;
    meta.chanspec = 0; meta.core_spatial = 0; meta.valid = 0;

    ap_uint<16> n_sub = 0;
    ap_uint<8>  b0 = 0, b1 = 0, b2 = 0;  // CSI byte assembly (4 bytes -> 1 sample)
    ap_uint<2>  phase = 0;

    parse: for (ap_uint<16> idx = 0; ; idx++) {
#pragma HLS PIPELINE II=1
        axis_byte beat = rx.read();
        ap_uint<8> b = beat.data;

        // Network-order header fields.
        if      (idx == 12) ethertype(15, 8) = b;
        else if (idx == 13) ethertype(7, 0)  = b;
        else if (idx == 23) ip_proto = b;              // IPv4 protocol (IHL=5 assumed)
        else if (idx == 36) dport(15, 8) = b;          // UDP dest port hi (14+20+2)
        else if (idx == 37) {
            dport(7, 0) = b;
            keep = (ethertype == 0x0800) && (ip_proto == 17) && (dport == udp_port);
        }
        // nexmon header (little-endian), payload begins at byte 42.
        else if (idx == 44) meta.rssi = (ap_int<8>)b;  // 42..43 magic, 44 rssi
        else if (idx == 52) meta.seq(7, 0)  = b;
        else if (idx == 53) meta.seq(15, 8) = b;
        else if (idx == 54) meta.core_spatial = b;
        else if (idx == 56) meta.chanspec(7, 0)  = b;
        else if (idx == 57) meta.chanspec(15, 8) = b;
        // CSI payload from byte 60: int16 LE real, int16 LE imag.
        else if (idx >= CSI_OFFSET && keep && n_sub < MAX_SUBCARRIERS) {
            if (phase == 0)      { b0 = b; phase = 1; }
            else if (phase == 1) { b1 = b; phase = 2; }
            else if (phase == 2) { b2 = b; phase = 3; }
            else {
                ap_int<16> re; re(7, 0) = b0; re(15, 8) = b1;
                ap_int<16> im; im(7, 0) = b2; im(15, 8) = b;
                axis_csi o;
                o.data(15, 0)  = (ap_uint<16>)re;
                o.data(31, 16) = (ap_uint<16>)im;
                o.keep = -1; o.strb = -1;
                o.last = beat.last;   // marks end-of-CSI (FCS assumed stripped)
                csi_out.write(o);
                n_sub++;
                phase = 0;
            }
        }

        if (beat.last) break;
    }

    if (keep && n_sub > 0) {
        meta.n_sub = n_sub;
        meta.valid = 1;
        meta_out.write(meta);
    }
}
