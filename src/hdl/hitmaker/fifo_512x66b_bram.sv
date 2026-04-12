//----------------------------------------------------------------------------
//-- FIFO : Uses Fifo Generator IP with Common clock, Fall-through, full, empty, level outputs
//-- 512 words x 66 bit
//----------------------------------------------------------------------------
`ifndef FIFO_512x66B__SV
`define FIFO_512x66B__SV

`timescale 1ns / 1ps

module fifo_512x66b
(
    input   logic           clk         , // 
    input   logic           srst        , // 

    input   logic  [65:0]   din         , // Input data
    input   logic           wr_en       , // Write

    input   logic           rd_en       , // Read
    output  logic  [65:0]   dout        , // Output data

    output  logic           full        , // Set as '1' when the FIFO is full
    output  logic           overflow    , // Set as '1' when write to full FIFO
    output  logic           empty       , // Set as '1' when the FIFO is empty
    output  logic           underflow   , // Set as '1' when read empty FIFO
    output  logic   [9:0]   data_count    // Number of words stored in FIFO
);

    // Xilinx IP catalog FIFO Generator using Common Clock Block RAM
    fifogen_512x66b_bram  u_fifo
    (
        .srst       ( srst          ),      // input  wire srst
        .clk        ( clk           ),      // input  wire clk
        .wr_en      ( wr_en         ),      // input  wire wr_en
        .din        ( din           ),      // input  wire [65 : 0] din
        .rd_en      ( rd_en         ),      // input  wire rd_en
        .dout       ( dout          ),      // output wire [65 : 0] dout
        .data_count ( data_count    ),      // output wire [9 : 0] data_count
        .full       ( full          ),      // output wire full
        .empty      ( empty         ),      // output wire empty
        .overflow   ( overflow      ),      // output wire overflow
        .underflow  ( underflow     )       // output wire underflow
    );
 
endmodule 

`endif