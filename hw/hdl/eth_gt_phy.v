// ---------------------------------------------------------------------------
// eth_gt_phy.v - GTY serial front end for the inline Arch-B AXI Ethernet MAC.
//
// This is work/hw/ref_axi_eth_example/eth_ex_support.v with the MAC taken out:
// the AXI Ethernet Subsystem 8.0 on Versal does NOT contain its own transceiver
// (CONFIG.GTinEx is locked true - "GT in Example design"), so the GT has to be
// supplied alongside it. The 2024.1 AMD reference design does that with a bare
// gt_quad_base wired to the MAC's gt_tx_interface / gt_rx_interface, but 8.0
// dropped those bundled interfaces; the supported 2025.2 arrangement is the
// gtwiz_versal wrapper instantiated below, whose INTF0_*/QUAD0_* ports line up
// with the MAC's discrete GT pins essentially one-for-one.
//
// The gtwiz IP itself is hw/ip/csi_eth_gtwiz.xci - the example design's .xci
// moved from quad channel 0 to channel 2, because VCK190 SFP0 is channel 2 of
// the bank 105 quad. That move cannot be made with set_property (the mapping
// parameters are "disabled"), so the file is edited; the refclk/PLL settings on
// top of it ARE set from Tcl, in hw/scripts/build_inline_xsa.tcl. See
// PROJECT_STATE.md section 11 for which parameters actually control the lane.
//
// Naming to watch: the interface-side ports keep lane-0 names (INTF0_TX0_ch_*,
// QUAD0_ch0_loopback) because they are interface lane 0, but the quad-side
// clocks follow the physical channel and are QUAD0_TX2_* / QUAD0_RX2_*. The
// QUAD0_{rxp,rxn,txp,txn}[3:0] serial buses are indexed by physical channel
// too, which is why SFP0 attaches to bit 2.
// ---------------------------------------------------------------------------
`timescale 1ps / 1ps

module eth_gt_phy (
    // --- board side -------------------------------------------------------
    input  wire        mgt_clk_p,        // 156.25 MHz SI570 GT refclk
    input  wire        mgt_clk_n,
    input  wire        sfp_rxp,
    input  wire        sfp_rxn,
    output wire        sfp_txp,
    output wire        sfp_txn,

    // --- control ----------------------------------------------------------
    input  wire        freerun_clk,      // MAC s_axi_lite_clk (100 MHz)
    input  wire        ref_clk,          // MAC ref_clk, clocks the pma_reset sync

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        resetn,           // MAC s_axi_lite_resetn (active low)

    // --- to/from the MAC (names match axi_ethernet 8.0 pins) --------------
    // Vivado infers pma_reset as a reset interface and would default it to
    // ACTIVE_LOW, which mismatches the MAC's ACTIVE_HIGH pin and fails
    // validate_bd_design; say so explicitly.
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 pma_reset RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    output wire        pma_reset,        // -> axi_eth/pma_reset
    output wire        mmcm_locked,      // -> axi_eth/mmcm_locked (tied high)
    output wire        userclk,          // -> axi_eth/userclk     (62.5 MHz)
    output wire        userclk2,         // -> axi_eth/userclk2    (125 MHz)
    output wire        rxuserclk,        // -> axi_eth/rxuserclk
    output wire        rxuserclk2,       // -> axi_eth/rxuserclk2
    output wire        gtpowergood,      // -> axi_eth/gtpowergood_in
    output wire        cplllock,         // -> axi_eth/cplllock_in
    output wire        gtwiz_reset_tx_done, // -> axi_eth/gtwiz_reset_tx_done_in
    output wire        gtwiz_reset_rx_done, // -> axi_eth/gtwiz_reset_rx_done_in

    input  wire [15:0] gtwiz_userdata_tx,   // <- axi_eth/gtwiz_userdata_tx_out
    output wire [15:0] gtwiz_userdata_rx,   // -> axi_eth/gtwiz_userdata_rx_in
    input  wire [15:0] txctrl0,             // <- axi_eth/txctrl0_out
    input  wire [15:0] txctrl1,
    input  wire [7:0]  txctrl2,
    output wire [15:0] rxctrl0,             // -> axi_eth/rxctrl0_in
    output wire [15:0] rxctrl1,
    output wire [7:0]  rxctrl2,
    output wire [7:0]  rxctrl3,
    output wire [1:0]  rxclkcorcnt,         // -> axi_eth/rxclkcorcnt_in
    output wire [1:0]  txbufstatus,         // -> axi_eth/txbufstatus_in
    output wire [2:0]  rxbufstatus,         // -> axi_eth/rxbufstatus_in
    input  wire [1:0]  txpd,                // <- axi_eth/txpd_out
    input  wire [1:0]  rxpd,                // <- axi_eth/rxpd_out
    input  wire        txelecidle,          // <- axi_eth/txelecidle_out
    output wire        txresetdone,         // -> axi_eth/txresetdone_in
    output wire        rxresetdone,         // -> axi_eth/rxresetdone_in
    output wire        txpmaresetdone,      // -> axi_eth/txpmaresetdone_in
    output wire        rxpmaresetdone,      // -> axi_eth/rxpmaresetdone_in
    input  wire        gtwiz_reset_tx_datapath, // <- axi_eth/gtwiz_reset_tx_datapath_out
    input  wire        gtwiz_reset_rx_datapath, // <- axi_eth/gtwiz_reset_rx_datapath_out
    input  wire        rxpcommaalignen,         // <- axi_eth/rxpcommaalignen_out

    // --- GT loopback control (runtime, from eth_loopback_gpio) --------------
    // 000 normal · 001 near-end PCS · 010 near-end PMA
    // 100 far-end PMA · 110 far-end PCS
    // Near-end PMA (010) is the one that closes TX->RX inside the transceiver
    // with no optics attached, which is what the self-test uses.
    input  wire [2:0]  loopback,

    // --- status, for eth_loopback_gpio channel 2 ---------------------------
    // Without this the GT is a black box: the MAC can report "link UP" over
    // MDIO while never transmitting a byte, and there is no way from software
    // to tell a stuck reset from a missing reference clock. The heartbeat
    // counters are the important part - if userclk2 or rxuserclk2 is not
    // running, its counter reads the same value twice and the GT clocking is
    // provably dead.
    output wire [31:0] status
);

    wire        gtrefclk;
    wire        gtrefclk_div;
    wire [3:0]  gtyrxp_in;
    wire [3:0]  gtyrxn_in;
    wire [3:0]  gtytxp_out;
    wire [3:0]  gtytxn_out;
    wire        QUAD0_TX2_outclk;
    wire        QUAD0_RX2_outclk;
    wire [15:0] gpi_gt;
    wire [127:0] rxdata_128;

    // SFP0 is physical channel 2 of the bank 105 quad.
    assign gtyrxp_in = {1'b0, sfp_rxp, 2'b00};
    assign gtyrxn_in = {1'b0, sfp_rxn, 2'b00};
    assign sfp_txp   = gtytxp_out[2];
    assign sfp_txn   = gtytxn_out[2];

    // The PCS drives comma alignment through the quad's GPI, bit 8.
    assign gpi_gt      = {7'h0, rxpcommaalignen, 8'h0};
    // No MMCM in this path - the GT supplies every clock - so report locked.
    assign mmcm_locked = 1'b1;
    assign gtwiz_userdata_rx = rxdata_128[15:0];

    // ---- PMA reset: asynchronous assert, synchronous release on ref_clk ----
    eth_gt_phy_reset_sync pma_reset_gen (
        .clk       (ref_clk),
        .reset_in  (~resetn | ~mmcm_locked),
        .reset_out (pma_reset)
    );

    // ---- GT reference clock buffer ----------------------------------------
    IBUFDS_GTE5 #(
        .REFCLK_EN_TX_PATH  (1'b0),
        .REFCLK_HROW_CK_SEL (0),
        .REFCLK_ICNTL_RX    (0)
    ) IBUFDS_GTE5_inst (
        .O    (gtrefclk),
        .ODIV2(gtrefclk_div),
        .CEB  (1'b0),
        .I    (mgt_clk_p),
        .IB   (mgt_clk_n)
    );

    // ---- Versal GT wizard (wraps gt_quad_base + its reset FSM) -------------
    csi_eth_gtwiz i_csi_eth_gtwiz (
        .gtpowergood                      (gtpowergood),
        .gtwiz_freerun_clk                (freerun_clk),
        .QUAD0_GTREFCLK0                  (gtrefclk),

        // The quad's APB register interface is unused: hold psel low.
        .QUAD0_apb3presetn                (pma_reset),
        .QUAD0_apb3paddr                  (16'h0),
        .QUAD0_apb3penable                (1'b0),
        .QUAD0_apb3prdata                 (),
        .QUAD0_apb3psel                   (1'b0),
        .QUAD0_apb3pslverr                (),
        .QUAD0_apb3pready                 (),
        .QUAD0_apb3pwdata                 (32'h0),
        .QUAD0_apb3pwrite                 (1'b0),

        .QUAD0_rxp                        (gtyrxp_in),
        .QUAD0_rxn                        (gtyrxn_in),
        .QUAD0_txp                        (gtytxp_out),
        .QUAD0_txn                        (gtytxn_out),
        .QUAD0_ch0_loopback               (loopback),
        .QUAD0_gpi                        (gpi_gt),
        .QUAD0_gpo                        (),
        // The GT runs off HSCLK1's RPLL (REFCLK_STRING = HSCLK1_RPLLGTREFCLK0),
        // so HSCLK1's lock is the one that means anything - the MAC gates its
        // reset FSM on cplllock_in, and taking HSCLK0's would be a silent
        // no-link. (The example design wires HSCLK0 because it runs the LCPLL.)
        .QUAD0_hsclk0_rplllock            (),
        .QUAD0_hsclk1_rplllock            (cplllock),
        .QUAD0_TX2_outclk                 (QUAD0_TX2_outclk),
        .QUAD0_RX2_outclk                 (QUAD0_RX2_outclk),
        .QUAD0_TX2_usrclk                 (userclk),
        .QUAD0_RX2_usrclk                 (userclk),

        .INTF0_TX0_ch_txdata              ({112'd0, gtwiz_userdata_tx}),
        .INTF0_TX0_ch_txbufstatus         (txbufstatus),
        .INTF0_TX0_ch_txprogdivresetdone  (gtwiz_reset_tx_done),
        .INTF0_TX0_ch_txresetdone         (txresetdone),
        .INTF0_TX0_ch_txpd                (txpd),
        .INTF0_TX0_ch_txrate              (8'h0),
        .INTF0_TX0_ch_txelecidle          (txelecidle),
        .INTF0_TX0_ch_txctrl0             (txctrl0),
        .INTF0_TX0_ch_txctrl1             (txctrl1),
        .INTF0_TX0_ch_txctrl2             (txctrl2),

        .INTF0_RX0_ch_rxbufstatus         (rxbufstatus),
        .INTF0_RX0_ch_rxpd                (rxpd),
        .INTF0_RX0_ch_rxrate              (8'h0),
        .INTF0_RX0_ch_rxdata              (rxdata_128),
        .INTF0_RX0_ch_rxclkcorcnt         (rxclkcorcnt),
        .INTF0_RX0_ch_rxcommadet          (),
        .INTF0_RX0_ch_rxbyteisaligned     (),
        .INTF0_RX0_ch_rxbyterealign       (),
        .INTF0_RX0_ch_rxctrl0             (rxctrl0),
        .INTF0_RX0_ch_rxctrl1             (rxctrl1),
        .INTF0_RX0_ch_rxctrl2             (rxctrl2),
        .INTF0_RX0_ch_rxctrl3             (rxctrl3),
        .INTF0_RX0_ch_rxprogdivresetdone  (gtwiz_reset_rx_done),
        .INTF0_RX0_ch_rxresetdone         (rxresetdone),

        .INTF0_TX_clr_out                 (),
        .INTF0_TX_clrb_leaf_out           (),
        .INTF0_RX_clr_out                 (),
        .INTF0_RX_clrb_leaf_out           (),
        .INTF0_rst_all_in                 (pma_reset),
        .INTF0_rst_tx_pll_and_datapath_in (1'b0),
        .INTF0_rst_tx_datapath_in         (gtwiz_reset_tx_datapath),
        .INTF0_rst_tx_done_out            (txpmaresetdone),
        .INTF0_rst_rx_pll_and_datapath_in (1'b0),
        .INTF0_rst_rx_datapath_in         (gtwiz_reset_rx_datapath),
        .INTF0_rst_rx_done_out            (rxpmaresetdone)
    );

    // ---- GT output clock buffers ------------------------------------------
    // TXOUTCLK is 125 MHz: userclk2 takes it straight, userclk is /2 (62.5 MHz).
    BUFG_GT #(.SIM_DEVICE("VERSAL_PREMIUM")) BUFG_GT_TX0_inst (
        .O(userclk2), .CE(1'b1), .CEMASK(1'b1), .CLR(1'b0), .CLRMASK(1'b1),
        .DIV(3'd0), .I(QUAD0_TX2_outclk));

    BUFG_GT #(.SIM_DEVICE("VERSAL_PREMIUM")) BUFG_GT_TX1_inst (
        .O(userclk), .CE(1'b1), .CEMASK(1'b1), .CLR(1'b0), .CLRMASK(1'b1),
        .DIV(3'd1), .I(QUAD0_TX2_outclk));

    BUFG_GT #(.SIM_DEVICE("VERSAL_PREMIUM")) BUFG_GT_RX0_inst (
        .O(rxuserclk2), .CE(1'b1), .CEMASK(1'b1), .CLR(1'b0), .CLRMASK(1'b1),
        .DIV(3'd0), .I(QUAD0_RX2_outclk));

    BUFG_GT #(.SIM_DEVICE("VERSAL_PREMIUM")) BUFG_GT_RX1_inst (
        .O(rxuserclk), .CE(1'b1), .CEMASK(1'b1), .CLR(1'b0), .CLRMASK(1'b1),
        .DIV(3'd0), .I(QUAD0_RX2_outclk));

    // --- status assembly -----------------------------------------------------
    // Heartbeats: free-running counters in each GT clock domain. Only the top
    // bits are exported, so they change slowly enough to compare across two
    // register reads. No CDC hardening needed - a torn read is fine, we only
    // ever ask "did this change?".
    (* ASYNC_REG = "TRUE" *) reg [15:0] hb_tx = 16'd0;
    (* ASYNC_REG = "TRUE" *) reg [15:0] hb_rx = 16'd0;
    always @(posedge userclk2)   hb_tx <= hb_tx + 16'd1;
    always @(posedge rxuserclk2) hb_rx <= hb_rx + 16'd1;

    assign status = {
        hb_rx[15:8],            // [31:24] rxuserclk2 heartbeat
        hb_tx[15:8],            // [23:16] userclk2 heartbeat
        5'b0,                   // [15:11]
        mmcm_locked,            // [10]
        resetn,                 // [9]
        pma_reset,              // [8]
        rxpmaresetdone,         // [7]
        txpmaresetdone,         // [6]
        rxresetdone,            // [5]
        txresetdone,            // [4]
        gtwiz_reset_rx_done,    // [3]
        gtwiz_reset_tx_done,    // [2]
        cplllock,               // [1]
        gtpowergood             // [0]
    };

endmodule


// Asynchronous assert / synchronous release reset synchroniser, active high.
// Copied from work/hw/ref_axi_eth_example/eth_ex_reset_sync.v.
module eth_gt_phy_reset_sync (
    input  wire clk,
    input  wire reset_in,
    output wire reset_out
);
    (* ASYNC_REG = "TRUE" *) reg rst_sync0 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg rst_sync1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg rst_sync2 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg rst_sync3 = 1'b0;
                             reg rst_sync4 = 1'b0;

    always @(posedge clk, posedge reset_in) begin
        if (reset_in) begin
            rst_sync0 <= 1'b1;
            rst_sync1 <= 1'b1;
            rst_sync2 <= 1'b1;
            rst_sync3 <= 1'b1;
        end else begin
            rst_sync0 <= 1'b0;
            rst_sync1 <= rst_sync0;
            rst_sync2 <= rst_sync1;
            rst_sync3 <= rst_sync2;
        end
    end

    always @(posedge clk) rst_sync4 <= rst_sync3;

    assign reset_out = rst_sync4;
endmodule
