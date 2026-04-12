//----------------------------------------------------------------------------
//-- FIFO : Common clock, Fall-through, full, empty, level outputs
//-- 16 words x 16 bit
//----------------------------------------------------------------------------
`ifndef FIFO_512X64B__SV
`define FIFO_512X64B__SV

`timescale 1ns / 1ps

module fifo_512x64b
(
    input   logic           clk         , // 
    input   logic           srst        , // 

    input   logic  [63:0]   din         , // Input data
    input   logic           wr_en       , // Write

    input   logic           rd_en       , // Read
    output  logic  [63:0]   dout        , // Output data

    output  logic           full        , // Set as '1' when the FIFO is full
    output  logic           overflow    , // Set as '1' when writing to full FIFO
    output  logic           empty       , // Set as '1' when the FIFO is empty
    output  logic           underflow   , // Set as '1' when reading an empty FIFO
    output  logic   [9:0]   data_count    // Number of words stored in FIFO
);

    localparam C_DEPTH      = 512;   // Depth of FIFO
    localparam C_WIDTH      =  64;   // Bitwidth of FIFO

    fifo_NxMbit  #(.G_DEPTH (C_DEPTH), .G_WIDTH (C_WIDTH) ) u_fifo 
    (
        .reset      ( srst          ) , 
        .clk        ( clk           ) , 
        .wr         ( wr_en         ) , 
        .data_in    ( din           ) ,   
        .rd         ( rd_en         ) , 
        .data_out   ( dout          ) , 
        .level      ( data_count    ) , 
        .empty      ( empty         ) , 
        .full       ( full          )  
    );  
    
    assign  overflow    = wr_en & full;
    assign  underflow   = rd_en & empty;

endmodule 

`endif
