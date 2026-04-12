`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/17/2021 01:11:15 AM
// Design Name: 
// Module Name: set_stream_size
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// Sets the hits per stream parameter on hitmaker based on 4 switch inputs. Switches are debounced,
// then parameter is calculated by multiplying switch input by 4096. Parameter will only change if 
// the decoder is idle. 
module set_stream_size(
    input   logic           clk,
    input   logic           reset,
    input   logic [ 3:0]    switches,
    output  logic [15:0]    stream_size
    );
    
    logic [ 3:0] switches_debounced;
    logic [31:0] random_32bit;
    logic [15:0] random_16bit;
    reg new_data;
    
    assign random_16bit = random_32bit[15:0];
    
    //------------------------------------------------------
    // Debounce all DIP switches
    //------------------------------------------------------
    genvar i;
    generate
        for (i=0; i<4; i++) begin : dip_switches
            debounce    u_debounce
            (
                .clk    (clk                    ),
                .reset  (reset                  ),  
                .sw_in  (switches[i]            ),  // input
                .sw_out (switches_debounced[i]  )   // output
            );
        end
    endgenerate

    
    //------------------------------------------------------
    // Random number generator for hits per stream
    //------------------------------------------------------
    rand32  u_rand32
    (
        .clk            (clk            ),
        .reset          (reset          ), 
        .restart        (1'b0           ), // input
        .seed           (32'hFFFFFFFF   ), // [31:0] input
        .step           (1'b1           ), // input
    
        .dout           (random_32bit   ), // [31:0] output
        .new_data       (new_data       )  // output reg
    );

    
    //------------------------------------------------------
    // Set hits per stream based on debounced switch inputs
    //------------------------------------------------------
    always_ff @(posedge clk) begin
        case (switches_debounced)
            4'hF :   stream_size <= 16'hFFFF                            ;
            4'hE :   stream_size <= 16'h7FFF                            ;
            4'hD :   stream_size <= 16'h3FFF                            ;
            4'hC :   stream_size <= 16'h1FFF                            ;
            4'hB :   stream_size <= 16'h0FFF                            ;
            4'hA :   stream_size <= 16'h07FF                            ;
            4'h9 :   stream_size <= 16'h03FF                            ;
            4'h8 :   stream_size <= 16'h01FF                            ;
            4'h7 :   stream_size <= 16'h00FF                            ;
            4'h6 :   stream_size <= 16'h007F                            ;
            4'h5 :   stream_size <= 16'h003F                            ;
            4'h4 :   stream_size <= 16'h001F                            ;
            4'h3 :   stream_size <= 16'h000F                            ;
            4'h2 :   stream_size <= 16'h0007                            ;
            4'h1 :   stream_size <= {7'b0000000, random_16bit[8:3], 3'b111}  ; // Random 0x0007 to 0x01FF, in steps of 7  (Assumes 512x64 FIFO in decoder)
            default: stream_size <= 16'h000F                            ;
        endcase
    end    
    
endmodule
