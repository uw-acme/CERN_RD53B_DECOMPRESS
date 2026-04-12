//----------------------------------------------------------------------------------------------------------------------
// [Filename]       Encoder.sv [RTL]
// [Project]        RD53B pixel ASIC
// [Author]         Geoff Jones geoffhjones@msn.com
// [Language]       SystemVerilog 2012 [IEEE Std. 1800-2012]
// [Created]        2/27/2021
// [Description]    Encodes 8x1 block of data with RD53B method
//
//----------------------------------------------------------------------------------------------------------------------
`ifndef ENC_8X1__SV
`define ENC_8X1__SV

`timescale 1ns / 1ps

//----------------------------------------------------------------------------------------------------------------------------------
// Encoder: Converts one 8-bit row of the 8x2 hit map into a variable length result (0 to 14 bits)
//----------------------------------------------------------------------------------------------------------------------------------
module enc_8x1
(
    input   wire            clk         ,
    input   wire    [ 7:0]  din         ,
    input   wire            din_dv      ,

    output  logic   [13:0]  dout        ,   // Output data. Packed into MSBs
    output  logic   [ 3:0]  dout_size       // Number of valid bits in dout
);

    always_ff @(posedge clk) 
    begin
        if (din_dv) begin

            case (din)
     
                8'b00000000: begin dout_size =  0; dout = 14'b00000000000000; end
                8'b00000001: begin dout_size =  3; dout = 14'b00000000000000; end
                8'b00000010: begin dout_size =  4; dout = 14'b00100000000000; end
                8'b00000011: begin dout_size =  4; dout = 14'b00110000000000; end
                8'b00000100: begin dout_size =  4; dout = 14'b01000000000000; end
                8'b00000101: begin dout_size =  5; dout = 14'b01100000000000; end
                8'b00000110: begin dout_size =  6; dout = 14'b01101000000000; end
                8'b00000111: begin dout_size =  6; dout = 14'b01101100000000; end
                8'b00001000: begin dout_size =  5; dout = 14'b01010000000000; end
                8'b00001001: begin dout_size =  6; dout = 14'b01110000000000; end
                8'b00001010: begin dout_size =  7; dout = 14'b01110100000000; end
                8'b00001011: begin dout_size =  7; dout = 14'b01110110000000; end
                8'b00001100: begin dout_size =  5; dout = 14'b01011000000000; end
                8'b00001101: begin dout_size =  6; dout = 14'b01111000000000; end
                8'b00001110: begin dout_size =  7; dout = 14'b01111100000000; end
                8'b00001111: begin dout_size =  7; dout = 14'b01111110000000; end
                8'b00010000: begin dout_size =  4; dout = 14'b10000000000000; end
                8'b00010001: begin dout_size =  6; dout = 14'b11000000000000; end
                8'b00010010: begin dout_size =  7; dout = 14'b11000100000000; end
                8'b00010011: begin dout_size =  7; dout = 14'b11000110000000; end
                8'b00010100: begin dout_size =  7; dout = 14'b11010000000000; end
                8'b00010101: begin dout_size =  8; dout = 14'b11011000000000; end
                8'b00010110: begin dout_size =  9; dout = 14'b11011001000000; end
                8'b00010111: begin dout_size =  9; dout = 14'b11011001100000; end
                8'b00011000: begin dout_size =  8; dout = 14'b11010010000000; end
                8'b00011001: begin dout_size =  9; dout = 14'b11011010000000; end
                8'b00011010: begin dout_size = 10; dout = 14'b11011010100000; end
                8'b00011011: begin dout_size = 10; dout = 14'b11011010110000; end
                8'b00011100: begin dout_size =  8; dout = 14'b11010011000000; end
                8'b00011101: begin dout_size =  9; dout = 14'b11011011000000; end
                8'b00011110: begin dout_size = 10; dout = 14'b11011011100000; end
                8'b00011111: begin dout_size = 10; dout = 14'b11011011110000; end
                8'b00100000: begin dout_size =  5; dout = 14'b10010000000000; end
                8'b00100001: begin dout_size =  7; dout = 14'b11001000000000; end
                8'b00100010: begin dout_size =  8; dout = 14'b11001010000000; end
                8'b00100011: begin dout_size =  8; dout = 14'b11001011000000; end
                8'b00100100: begin dout_size =  8; dout = 14'b11010100000000; end
                8'b00100101: begin dout_size =  9; dout = 14'b11011100000000; end
                8'b00100110: begin dout_size = 10; dout = 14'b11011100100000; end
                8'b00100111: begin dout_size = 10; dout = 14'b11011100110000; end
                8'b00101000: begin dout_size =  9; dout = 14'b11010101000000; end
                8'b00101001: begin dout_size = 10; dout = 14'b11011101000000; end
                8'b00101010: begin dout_size = 11; dout = 14'b11011101010000; end
                8'b00101011: begin dout_size = 11; dout = 14'b11011101011000; end
                8'b00101100: begin dout_size =  9; dout = 14'b11010101100000; end
                8'b00101101: begin dout_size = 10; dout = 14'b11011101100000; end
                8'b00101110: begin dout_size = 11; dout = 14'b11011101110000; end
                8'b00101111: begin dout_size = 11; dout = 14'b11011101111000; end
                8'b00110000: begin dout_size =  5; dout = 14'b10011000000000; end
                8'b00110001: begin dout_size =  7; dout = 14'b11001100000000; end
                8'b00110010: begin dout_size =  8; dout = 14'b11001110000000; end
                8'b00110011: begin dout_size =  8; dout = 14'b11001111000000; end
                8'b00110100: begin dout_size =  8; dout = 14'b11010110000000; end
                8'b00110101: begin dout_size =  9; dout = 14'b11011110000000; end
                8'b00110110: begin dout_size = 10; dout = 14'b11011110100000; end
                8'b00110111: begin dout_size = 10; dout = 14'b11011110110000; end
                8'b00111000: begin dout_size =  9; dout = 14'b11010111000000; end
                8'b00111001: begin dout_size = 10; dout = 14'b11011111000000; end
                8'b00111010: begin dout_size = 11; dout = 14'b11011111010000; end
                8'b00111011: begin dout_size = 11; dout = 14'b11011111011000; end
                8'b00111100: begin dout_size =  9; dout = 14'b11010111100000; end
                8'b00111101: begin dout_size = 10; dout = 14'b11011111100000; end
                8'b00111110: begin dout_size = 11; dout = 14'b11011111110000; end
                8'b00111111: begin dout_size = 11; dout = 14'b11011111111000; end
                8'b01000000: begin dout_size =  5; dout = 14'b10100000000000; end
                8'b01000001: begin dout_size =  7; dout = 14'b11100000000000; end
                8'b01000010: begin dout_size =  8; dout = 14'b11100010000000; end
                8'b01000011: begin dout_size =  8; dout = 14'b11100011000000; end
                8'b01000100: begin dout_size =  8; dout = 14'b11101000000000; end
                8'b01000101: begin dout_size =  9; dout = 14'b11101100000000; end
                8'b01000110: begin dout_size = 10; dout = 14'b11101100100000; end
                8'b01000111: begin dout_size = 10; dout = 14'b11101100110000; end
                8'b01001000: begin dout_size =  9; dout = 14'b11101001000000; end
                8'b01001001: begin dout_size = 10; dout = 14'b11101101000000; end
                8'b01001010: begin dout_size = 11; dout = 14'b11101101010000; end
                8'b01001011: begin dout_size = 11; dout = 14'b11101101011000; end
                8'b01001100: begin dout_size =  9; dout = 14'b11101001100000; end
                8'b01001101: begin dout_size = 10; dout = 14'b11101101100000; end
                8'b01001110: begin dout_size = 11; dout = 14'b11101101110000; end
                8'b01001111: begin dout_size = 11; dout = 14'b11101101111000; end
                8'b01010000: begin dout_size =  6; dout = 14'b10110000000000; end
                8'b01010001: begin dout_size =  8; dout = 14'b11110000000000; end
                8'b01010010: begin dout_size =  9; dout = 14'b11110001000000; end
                8'b01010011: begin dout_size =  9; dout = 14'b11110001100000; end
                8'b01010100: begin dout_size =  9; dout = 14'b11111000000000; end
                8'b01010101: begin dout_size = 10; dout = 14'b11111100000000; end
                8'b01010110: begin dout_size = 11; dout = 14'b11111100010000; end
                8'b01010111: begin dout_size = 11; dout = 14'b11111100011000; end
                8'b01011000: begin dout_size = 10; dout = 14'b11111000100000; end
                8'b01011001: begin dout_size = 11; dout = 14'b11111100100000; end
                8'b01011010: begin dout_size = 12; dout = 14'b11111100101000; end
                8'b01011011: begin dout_size = 12; dout = 14'b11111100101100; end
                8'b01011100: begin dout_size = 10; dout = 14'b11111000110000; end
                8'b01011101: begin dout_size = 11; dout = 14'b11111100110000; end
                8'b01011110: begin dout_size = 12; dout = 14'b11111100111000; end
                8'b01011111: begin dout_size = 12; dout = 14'b11111100111100; end
                8'b01100000: begin dout_size =  7; dout = 14'b10110100000000; end
                8'b01100001: begin dout_size =  9; dout = 14'b11110010000000; end
                8'b01100010: begin dout_size = 10; dout = 14'b11110010100000; end
                8'b01100011: begin dout_size = 10; dout = 14'b11110010110000; end
                8'b01100100: begin dout_size = 10; dout = 14'b11111001000000; end
                8'b01100101: begin dout_size = 11; dout = 14'b11111101000000; end
                8'b01100110: begin dout_size = 12; dout = 14'b11111101001000; end
                8'b01100111: begin dout_size = 12; dout = 14'b11111101001100; end
                8'b01101000: begin dout_size = 11; dout = 14'b11111001010000; end
                8'b01101001: begin dout_size = 12; dout = 14'b11111101010000; end
                8'b01101010: begin dout_size = 13; dout = 14'b11111101010100; end
                8'b01101011: begin dout_size = 13; dout = 14'b11111101010110; end
                8'b01101100: begin dout_size = 11; dout = 14'b11111001011000; end
                8'b01101101: begin dout_size = 12; dout = 14'b11111101011000; end
                8'b01101110: begin dout_size = 13; dout = 14'b11111101011100; end
                8'b01101111: begin dout_size = 13; dout = 14'b11111101011110; end
                8'b01110000: begin dout_size =  7; dout = 14'b10110110000000; end
                8'b01110001: begin dout_size =  9; dout = 14'b11110011000000; end
                8'b01110010: begin dout_size = 10; dout = 14'b11110011100000; end
                8'b01110011: begin dout_size = 10; dout = 14'b11110011110000; end
                8'b01110100: begin dout_size = 10; dout = 14'b11111001100000; end
                8'b01110101: begin dout_size = 11; dout = 14'b11111101100000; end
                8'b01110110: begin dout_size = 12; dout = 14'b11111101101000; end
                8'b01110111: begin dout_size = 12; dout = 14'b11111101101100; end
                8'b01111000: begin dout_size = 11; dout = 14'b11111001110000; end
                8'b01111001: begin dout_size = 12; dout = 14'b11111101110000; end
                8'b01111010: begin dout_size = 13; dout = 14'b11111101110100; end
                8'b01111011: begin dout_size = 13; dout = 14'b11111101110110; end
                8'b01111100: begin dout_size = 11; dout = 14'b11111001111000; end
                8'b01111101: begin dout_size = 12; dout = 14'b11111101111000; end
                8'b01111110: begin dout_size = 13; dout = 14'b11111101111100; end
                8'b01111111: begin dout_size = 13; dout = 14'b11111101111110; end
                8'b10000000: begin dout_size =  6; dout = 14'b10101000000000; end
                8'b10000001: begin dout_size =  8; dout = 14'b11100100000000; end
                8'b10000010: begin dout_size =  9; dout = 14'b11100101000000; end
                8'b10000011: begin dout_size =  9; dout = 14'b11100101100000; end
                8'b10000100: begin dout_size =  9; dout = 14'b11101010000000; end
                8'b10000101: begin dout_size = 10; dout = 14'b11101110000000; end
                8'b10000110: begin dout_size = 11; dout = 14'b11101110010000; end
                8'b10000111: begin dout_size = 11; dout = 14'b11101110011000; end
                8'b10001000: begin dout_size = 10; dout = 14'b11101010100000; end
                8'b10001001: begin dout_size = 11; dout = 14'b11101110100000; end
                8'b10001010: begin dout_size = 12; dout = 14'b11101110101000; end
                8'b10001011: begin dout_size = 12; dout = 14'b11101110101100; end
                8'b10001100: begin dout_size = 10; dout = 14'b11101010110000; end
                8'b10001101: begin dout_size = 11; dout = 14'b11101110110000; end
                8'b10001110: begin dout_size = 12; dout = 14'b11101110111000; end
                8'b10001111: begin dout_size = 12; dout = 14'b11101110111100; end
                8'b10010000: begin dout_size =  7; dout = 14'b10111000000000; end
                8'b10010001: begin dout_size =  9; dout = 14'b11110100000000; end
                8'b10010010: begin dout_size = 10; dout = 14'b11110100100000; end
                8'b10010011: begin dout_size = 10; dout = 14'b11110100110000; end
                8'b10010100: begin dout_size = 10; dout = 14'b11111010000000; end
                8'b10010101: begin dout_size = 11; dout = 14'b11111110000000; end
                8'b10010110: begin dout_size = 12; dout = 14'b11111110001000; end
                8'b10010111: begin dout_size = 12; dout = 14'b11111110001100; end
                8'b10011000: begin dout_size = 11; dout = 14'b11111010010000; end
                8'b10011001: begin dout_size = 12; dout = 14'b11111110010000; end
                8'b10011010: begin dout_size = 13; dout = 14'b11111110010100; end
                8'b10011011: begin dout_size = 13; dout = 14'b11111110010110; end
                8'b10011100: begin dout_size = 11; dout = 14'b11111010011000; end
                8'b10011101: begin dout_size = 12; dout = 14'b11111110011000; end
                8'b10011110: begin dout_size = 13; dout = 14'b11111110011100; end
                8'b10011111: begin dout_size = 13; dout = 14'b11111110011110; end
                8'b10100000: begin dout_size =  8; dout = 14'b10111010000000; end
                8'b10100001: begin dout_size = 10; dout = 14'b11110101000000; end
                8'b10100010: begin dout_size = 11; dout = 14'b11110101010000; end
                8'b10100011: begin dout_size = 11; dout = 14'b11110101011000; end
                8'b10100100: begin dout_size = 11; dout = 14'b11111010100000; end
                8'b10100101: begin dout_size = 12; dout = 14'b11111110100000; end
                8'b10100110: begin dout_size = 13; dout = 14'b11111110100100; end
                8'b10100111: begin dout_size = 13; dout = 14'b11111110100110; end
                8'b10101000: begin dout_size = 12; dout = 14'b11111010101000; end
                8'b10101001: begin dout_size = 13; dout = 14'b11111110101000; end
                8'b10101010: begin dout_size = 14; dout = 14'b11111110101010; end
                8'b10101011: begin dout_size = 14; dout = 14'b11111110101011; end
                8'b10101100: begin dout_size = 12; dout = 14'b11111010101100; end
                8'b10101101: begin dout_size = 13; dout = 14'b11111110101100; end
                8'b10101110: begin dout_size = 14; dout = 14'b11111110101110; end
                8'b10101111: begin dout_size = 14; dout = 14'b11111110101111; end
                8'b10110000: begin dout_size =  8; dout = 14'b10111011000000; end
                8'b10110001: begin dout_size = 10; dout = 14'b11110101100000; end
                8'b10110010: begin dout_size = 11; dout = 14'b11110101110000; end
                8'b10110011: begin dout_size = 11; dout = 14'b11110101111000; end
                8'b10110100: begin dout_size = 11; dout = 14'b11111010110000; end
                8'b10110101: begin dout_size = 12; dout = 14'b11111110110000; end
                8'b10110110: begin dout_size = 13; dout = 14'b11111110110100; end
                8'b10110111: begin dout_size = 13; dout = 14'b11111110110110; end
                8'b10111000: begin dout_size = 12; dout = 14'b11111010111000; end
                8'b10111001: begin dout_size = 13; dout = 14'b11111110111000; end
                8'b10111010: begin dout_size = 14; dout = 14'b11111110111010; end
                8'b10111011: begin dout_size = 14; dout = 14'b11111110111011; end
                8'b10111100: begin dout_size = 12; dout = 14'b11111010111100; end
                8'b10111101: begin dout_size = 13; dout = 14'b11111110111100; end
                8'b10111110: begin dout_size = 14; dout = 14'b11111110111110; end
                8'b10111111: begin dout_size = 14; dout = 14'b11111110111111; end
                8'b11000000: begin dout_size =  6; dout = 14'b10101100000000; end
                8'b11000001: begin dout_size =  8; dout = 14'b11100110000000; end
                8'b11000010: begin dout_size =  9; dout = 14'b11100111000000; end
                8'b11000011: begin dout_size =  9; dout = 14'b11100111100000; end
                8'b11000100: begin dout_size =  9; dout = 14'b11101011000000; end
                8'b11000101: begin dout_size = 10; dout = 14'b11101111000000; end
                8'b11000110: begin dout_size = 11; dout = 14'b11101111010000; end
                8'b11000111: begin dout_size = 11; dout = 14'b11101111011000; end
                8'b11001000: begin dout_size = 10; dout = 14'b11101011100000; end
                8'b11001001: begin dout_size = 11; dout = 14'b11101111100000; end
                8'b11001010: begin dout_size = 12; dout = 14'b11101111101000; end
                8'b11001011: begin dout_size = 12; dout = 14'b11101111101100; end
                8'b11001100: begin dout_size = 10; dout = 14'b11101011110000; end
                8'b11001101: begin dout_size = 11; dout = 14'b11101111110000; end
                8'b11001110: begin dout_size = 12; dout = 14'b11101111111000; end
                8'b11001111: begin dout_size = 12; dout = 14'b11101111111100; end
                8'b11010000: begin dout_size =  7; dout = 14'b10111100000000; end
                8'b11010001: begin dout_size =  9; dout = 14'b11110110000000; end
                8'b11010010: begin dout_size = 10; dout = 14'b11110110100000; end
                8'b11010011: begin dout_size = 10; dout = 14'b11110110110000; end
                8'b11010100: begin dout_size = 10; dout = 14'b11111011000000; end
                8'b11010101: begin dout_size = 11; dout = 14'b11111111000000; end
                8'b11010110: begin dout_size = 12; dout = 14'b11111111001000; end
                8'b11010111: begin dout_size = 12; dout = 14'b11111111001100; end
                8'b11011000: begin dout_size = 11; dout = 14'b11111011010000; end
                8'b11011001: begin dout_size = 12; dout = 14'b11111111010000; end
                8'b11011010: begin dout_size = 13; dout = 14'b11111111010100; end
                8'b11011011: begin dout_size = 13; dout = 14'b11111111010110; end
                8'b11011100: begin dout_size = 11; dout = 14'b11111011011000; end
                8'b11011101: begin dout_size = 12; dout = 14'b11111111011000; end
                8'b11011110: begin dout_size = 13; dout = 14'b11111111011100; end
                8'b11011111: begin dout_size = 13; dout = 14'b11111111011110; end
                8'b11100000: begin dout_size =  8; dout = 14'b10111110000000; end
                8'b11100001: begin dout_size = 10; dout = 14'b11110111000000; end
                8'b11100010: begin dout_size = 11; dout = 14'b11110111010000; end
                8'b11100011: begin dout_size = 11; dout = 14'b11110111011000; end
                8'b11100100: begin dout_size = 11; dout = 14'b11111011100000; end
                8'b11100101: begin dout_size = 12; dout = 14'b11111111100000; end
                8'b11100110: begin dout_size = 13; dout = 14'b11111111100100; end
                8'b11100111: begin dout_size = 13; dout = 14'b11111111100110; end
                8'b11101000: begin dout_size = 12; dout = 14'b11111011101000; end
                8'b11101001: begin dout_size = 13; dout = 14'b11111111101000; end
                8'b11101010: begin dout_size = 14; dout = 14'b11111111101010; end
                8'b11101011: begin dout_size = 14; dout = 14'b11111111101011; end
                8'b11101100: begin dout_size = 12; dout = 14'b11111011101100; end
                8'b11101101: begin dout_size = 13; dout = 14'b11111111101100; end
                8'b11101110: begin dout_size = 14; dout = 14'b11111111101110; end
                8'b11101111: begin dout_size = 14; dout = 14'b11111111101111; end
                8'b11110000: begin dout_size =  8; dout = 14'b10111111000000; end
                8'b11110001: begin dout_size = 10; dout = 14'b11110111100000; end
                8'b11110010: begin dout_size = 11; dout = 14'b11110111110000; end
                8'b11110011: begin dout_size = 11; dout = 14'b11110111111000; end
                8'b11110100: begin dout_size = 11; dout = 14'b11111011110000; end
                8'b11110101: begin dout_size = 12; dout = 14'b11111111110000; end
                8'b11110110: begin dout_size = 13; dout = 14'b11111111110100; end
                8'b11110111: begin dout_size = 13; dout = 14'b11111111110110; end
                8'b11111000: begin dout_size = 12; dout = 14'b11111011111000; end
                8'b11111001: begin dout_size = 13; dout = 14'b11111111111000; end
                8'b11111010: begin dout_size = 14; dout = 14'b11111111111010; end
                8'b11111011: begin dout_size = 14; dout = 14'b11111111111011; end
                8'b11111100: begin dout_size = 12; dout = 14'b11111011111100; end
                8'b11111101: begin dout_size = 13; dout = 14'b11111111111100; end
                8'b11111110: begin dout_size = 14; dout = 14'b11111111111110; end
                8'b11111111: begin dout_size = 14; dout = 14'b11111111111111; end
            endcase
        
        end 
    end 

endmodule 

`endif
