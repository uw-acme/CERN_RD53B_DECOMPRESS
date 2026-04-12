//----------------------------------------------------------------------------
//-- FIFO : Common clock, Fall-through, full, empty, level outputs
//-- 16 words x 128 bit, built with distributed RAM
//----------------------------------------------------------------------------
`ifndef FIFO_ASSEM__SV
`define FIFO_ASSEM__SV

`timescale 1ns / 1ps

module fifo_assem
(
    input   logic           clk         , // 
    input   logic           srst        , // 

    input   logic [127:0]   din         , // Input data
    input   logic           wr_en       , // Write

    input   logic           rd_en       , // Read
    output  logic [127:0]   dout        , // Output data

    output  logic           full        , // Set as '1' when the FIFO is full
    output  logic           overflow    , // Set as '1' when write to full FIFO
    output  logic           empty       , // Set as '1' when the FIFO is empty
    output  logic           underflow   , // Set as '1' when read empty FIFO
    output  logic   [9:0]   data_count    // Number of words stored in FIFO
);

    localparam C_DEPTH      =  16;   // Depth of FIFO
    localparam C_WIDTH      = 128;   // Bitwidth of FIFO

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
