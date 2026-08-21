// ---------------------------------------------------------------------------
// axis_sink.v - an AXI4-Stream slave that accepts and discards everything.
//
// Used to terminate the AXI Ethernet Subsystem's m_axis_rxs (RX status) stream.
// The MAC emits one status word per received frame regardless of whether anyone
// consumes it; if that stream is left unconnected the RX path back-pressures
// and stalls the whole inline CSI datapath, so it must be drained, not dangled.
//
// TREADY is tied high (never back-pressures); the data is simply dropped, so
// synthesis trims the module down to that one constant.
// ---------------------------------------------------------------------------
`timescale 1ns / 1ps

module axis_sink #(
    parameter integer TDATA_WIDTH = 32
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axis, ASSOCIATED_RESET aresetn" *)
    input  wire                       aclk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire                       aresetn,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TVALID" *)
    input  wire                       s_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TREADY" *)
    output wire                       s_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TDATA" *)
    input  wire [TDATA_WIDTH-1:0]     s_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TKEEP" *)
    input  wire [(TDATA_WIDTH/8)-1:0] s_axis_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TLAST" *)
    input  wire                       s_axis_tlast
);

    assign s_axis_tready = 1'b1;

endmodule
