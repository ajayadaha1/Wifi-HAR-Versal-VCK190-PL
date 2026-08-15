// Copyright (C) 2021 Xilinx Inc.
// Copyright (C) 2022, Advanced Micro Devices, Inc.

module rxcommaalignen_out_shifter (
    input wire rxcommaalignen_in,
    output wire [15:0] gpi_out
);

// ORIGINAL assign gpi_out = {5'b0,rxcommaalignen_in,10'b0};

// Now connecting signal to GPIO[6]
//assign gpi_out = {9'b0,rxcommaalignen_in,6'b0};

assign gpi_out = {5'b0,rxcommaalignen_in,10'b0};
endmodule

