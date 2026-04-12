//----------------------------------------------------------------------------------------------------------------------
// [Filename]       env_2bit.sv [RTL]
// [Project]        RD53B pixel ASIC
// [Author]         Geoff Jones geoffhjones@msn.com
// [Language]       SystemVerilog 2012 [IEEE Std. 1800-2012]
// [Created]        2/27/2021
// [Description]    Encodes 8x1 block of data with RD53B method
//
//----------------------------------------------------------------------------------------------------------------------
`ifndef ENC_2BIT__SV
`define ENC_2BIT__SV

`timescale 1ns / 1ps

//----------------------------------------------------------------------------------------------------------------------------------
// Encoder: Converts 2-bits section of hit map into a variable length result (0 to 14 bits)
//----------------------------------------------------------------------------------------------------------------------------------
module enc_2bit
(
    input   wire            clk         ,
    input   wire    [ 1:0]  din         ,
    input   wire            din_dv      ,

    output  logic   [ 1:0]  dout        ,   // Output data. Packed into MSBs
    output  logic   [ 1:0]  dout_size       // Number of valid bits in dout
);

    always_ff @(posedge clk) 
    begin
        if (din_dv) begin

            case (din)
     
                2'b00: begin dout_size =  0; dout = 2'b00; end
                2'b01: begin dout_size =  1; dout = 2'b00; end
                2'b10: begin dout_size =  2; dout = 2'b10; end
                2'b11: begin dout_size =  2; dout = 2'b11; end

            endcase
        end 
        
    end 

endmodule 

`endif
