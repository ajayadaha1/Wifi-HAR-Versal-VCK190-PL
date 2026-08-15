// PL data mover: AXI4-Stream from AIE PLIO_out (32-bit words) -> DDR (AXI4-MM).
// Drains `size` result words (fp32: {mean, variance, power}) back to memory.
#include <ap_int.h>
#include <ap_axi_sdata.h>
#include <hls_stream.h>

extern "C" void s2mm(ap_uint<32>* mem, hls::stream<ap_axiu<32, 0, 0, 0>>& s, int size) {
#pragma HLS INTERFACE m_axi port=mem offset=slave bundle=gmem
#pragma HLS INTERFACE s_axilite port=mem bundle=control
#pragma HLS INTERFACE s_axilite port=size bundle=control
#pragma HLS INTERFACE axis port=s
#pragma HLS INTERFACE s_axilite port=return bundle=control
    for (int i = 0; i < size; i++) {
#pragma HLS PIPELINE II=1
        ap_axiu<32, 0, 0, 0> v = s.read();
        mem[i] = v.data;
    }
}
