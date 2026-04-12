//----------------------------------------------------------------------------------------------------------------------
// [Filename]       hitdecode.sv [RTL]
// [Project]        Stream Decoder for RD53B data in an FPGA
// [Author]         
// [Language]       SystemVerilog 2012 [IEEE Std. 1800-2012]
// [Created]        
// [Description]    Decode a compressed/encoded hitmap into original 16-bit qrow data, together with encoded size and
//                  number of bits set in original qrow.
//
//                  Block receives a 30-bit input word which contains a compressed hitmap.
//                  The hitmap length (number of MSBits) is unknown and can vary in length from 5 to 30.
//                  The input channel is associated with a decoder engine in another block and is transferred to
//                  the output, with the uncompressed hitmap, to identify the engine that will use the result.
//
//                  The block has a fixed length pipeline and can accept new data on every clock cycle.
//                  The output consists of the decoded hitmap, the calculated length of the input hitmap, and
//                  the number of set bits (hits) in the resulting output hitmap.
//
//                  It is known that the first 2 MSBs of the input contain information about the rows in the qrow block
//                  that contain hits. The subsequent bits could be the encoded 'upper' row, the 'lower' row, or upper 
//                  followed by lower. Either row has a maximum encoded length of 14-bits and two 4K (14-bit address) ROMs
//                  are used to decompress each row. The ROMs contain the 8-bit decoded hitmap for one row and information
//                  about the length of the compressed hitmap.
//      
// Author      : G. Jones
//----------------------------------------------------------------------------------------------------------------------
`ifndef HITDECODE__SV
`define HITDECODE__SV

`timescale 1ns / 1ps

module hitdecode (
    input                   clk             ,
    input                   reset           ,

    input                   reg_en_encode   ,   // '0' if Input is not encoded. Output is always 16 MSBs

    input   [29:0]          data_in         ,   // Contains input hitmap in MSBs. Actual size is unknown. 5 bits min, 30 bits max
    input   [ 3:0]          data_in_chan    ,   // Channel number of input hitmap data
    input                   data_in_dv      ,   // Input data valid
    
    output  reg [15:0]      hitmap_out      ,   // Decoded hitmap
    output  reg [ 4:0]      hitmap_length   ,   // Actual length of the compressed input hitmap (4 to 30)
    output  reg [ 4:0]      hitmap_nbits    ,   // Number of bits set in the decoded hitmap. (1 to 16)
    output  reg [ 3:0]      hitmap_out_chan ,   // Channel number of output hitmap
    output  reg             hitmap_out_dv       // Output data valid
);

    logic           flag_no_row1, flag_no_row1_d1, flag_no_row1_d2, flag_no_row1_d3;
    logic           flag_no_row2, flag_no_row2_d1, flag_no_row2_d2, flag_no_row2_d3;

    logic   [13:0]  rom_addr1, rom_addr2;

    //------------------------------------------------------
    // ROM output is 
    //   hit_pat[7:0]    1 - 255   0x01 to 0xFF
    //   hit_size[3:0]   4 - 14    0x4  to 0xD 
    //   hit_nbits[3:0]  1 - 16    0x0  to 0xF  (zero = 1 bit set)
    //------------------------------------------------------
    logic   [15:0]  rom_dout1, rom_dout2;
    logic   [ 7:0]  hit_pat1,   hit_pat2;
    logic   [ 3:0]  hit_size1,  hit_size2;
    logic   [ 3:0]  hit_nbits1, hit_nbits2;

    // Pipeline regs for channel number
    logic   [ 3:0]  chan_d1, chan_d2, chan_d3, chan_d4; 
    logic           data_in_dv_d1, data_in_dv_d2, data_in_dv_d3, data_in_dv_d4; 
    logic   [27:0]  data_in_d1, data_in_d2 ; 
    logic   [15:0]  data16_d1, data16_d2, data16_d3, data16_d4;     // Registers to pipeline unencoded 16-bit hitmap

    // Pipeline regs for row1 ROM output
    logic   [ 7:0]  hit_pat1_d1,    hit_pat1_d2;
    logic   [ 3:0]  hit_size1_d1,   hit_size1_d2;
    logic   [ 3:0]  hit_nbits1_d1,  hit_nbits1_d2;


    //----------------------------------------------------------------------------------------------------------------------
    // Select address bits for first row ROM lookup
    // If MSB is '0' then this means '01' for the first node which was compressed to a single '0'.
    // This means no data in row 1, data in row2 
    //----------------------------------------------------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin
        if (reset) begin
            rom_addr1       <= 14'b00000000000000;
            flag_no_row1    <= 1'b0;
            flag_no_row2    <= 1'b0;
            data_in_d1      <= 0;

        end else if (data_in_dv == 1'b1) begin

            //----------------------------------------------------------------------------------------------------
            // First two MSBs tells us whether hits are present in row1 or row2 or both
            // *** If the pattern begins with a '00' or '01' then it means that the first two bits
            //     of the partially encoded hitmap were '01', and this pattern is finally encoded as a single '0'.
            //     This means that "00" and "01" are really "010" and "011", where the third bit is the first bit
            //     in the second row. (Since there is no first row data)
            //----------------------------------------------------------------------------------------------------
            case (data_in[29:28])

                // The first '0' is encoded from '01'. Second '0' is '01' of row2 encoding
                // No bits set in row1. Bits must be set in row2. First bit in row2 is data_in[28] = '0'
                2'b00   : begin
                            rom_addr1     <= 14'b0;  
                            flag_no_row1  <= 1'b1;
                            flag_no_row2  <= 1'b0;
                            data_in_d1    <= {data_in[28:15], 14'b0}; // 28-bit
                end
                
                // The first '0' is encoded from '01'. Second '1' is '01' of row2 encoding
                // No bits set in row1. Bits must be set in row2. First bit in row2 is data_in[28] = '1'
                // (Same as 2'b00)
                2'b01   : begin
                            rom_addr1     <= 14'b0;  
                            flag_no_row1  <= 1'b1;
                            flag_no_row2  <= 1'b0;
                            data_in_d1    <= {data_in[28:15], 14'b0};
                end
                
                // Bits set in row1. No bits set in row2. First bit in row1 is data_in[27]
                2'b10   : begin
                            rom_addr1     <= data_in[27:14];  // Use 14 bits as address  
                            flag_no_row1  <= 1'b0;
                            flag_no_row2  <= 1'b1;
                            data_in_d1    <= data_in[27:0];
                end

                // Bits set in row1 and row2. First bit in row1 is data_in[27]
                2'b11   : begin
                            rom_addr1     <= data_in[27:14];  
                            flag_no_row1  <= 1'b0;
                            flag_no_row2  <= 1'b0;
                            data_in_d1    <= data_in[27:0];
                end

                default : begin
                            rom_addr1     <= 14'bX; 
                            flag_no_row1  <= 1'bX;
                            flag_no_row2  <= 1'bX;
                            data_in_d1    <= 28'bX;
                end
                
            endcase;                                     

        end else begin
            rom_addr1     <= 14'bX; 
            flag_no_row1  <= 1'b0;
            flag_no_row2  <= 1'b0;
            data_in_d1    <= 28'bX;
        end

    end


    //----------------------------------------------------------------------------------------------------------------------
    // ROM used for decoding the first/upper row with one port, and second/lower row with second port.
    // 14-bit address input. 16-bit data output.
    //----------------------------------------------------------------------------------------------------------------------
    rom_hitdecode  u_rom_hitdecode 
    (
        .clka   (clk        ),  
        .addra  (rom_addr1  ),      // input  wire [13:0]
        .douta  (rom_dout1  ),      // output wire [15:0]
        .clkb   (clk        ),      // input  wire 
        .addrb  (rom_addr2  ),      // input  wire [13:0] 
        .doutb  (rom_dout2  )       // output wire [15:0] 
    );

    // Breakout fields from both ROM outputs
    assign hit_pat1     = rom_dout1[7:0];
    assign hit_size1    = rom_dout1[11:8];
    assign hit_nbits1   = rom_dout1[15:12];

    assign hit_pat2     = rom_dout2[7:0];
    assign hit_size2    = rom_dout2[11:8];
    assign hit_nbits2   = rom_dout2[15:12];


    //----------------------------------------------------------------------------------------------------------------------
    // Select address bits for second row ROM lookup
    //----------------------------------------------------------------------------------------------------------------------
    always @(posedge clk) 
    begin
        if (reset) begin
            rom_addr2       <= 14'b00000000000000;

        end else begin

            if (flag_no_row1_d1 == 1'b1) begin
                rom_addr2     <= data_in_d2[27:14]; // Size of row1 = 0
            end 
            else begin

                // The first row uses a minimum of 3 bits or a maximum of 14 bits
                case (hit_size1)

                    4'b0011 : rom_addr2     <= data_in_d2[24:11]; // Size = 3. Remove upper 3 bits (used in row1)
                    4'b0100 : rom_addr2     <= data_in_d2[23:10]; // Size = 4. Remove upper 4 bits (used in row1)
                    4'b0101 : rom_addr2     <= data_in_d2[22: 9]; // Size = 5. Remove upper 5 bits  
                    4'b0110 : rom_addr2     <= data_in_d2[21: 8]; // Size = 6. Remove upper 6 bits  
                    4'b0111 : rom_addr2     <= data_in_d2[20: 7]; // Size = 7. Remove upper 7 bits  
                    4'b1000 : rom_addr2     <= data_in_d2[19: 6]; // Size = 8. Remove upper 8 bits  
                    4'b1001 : rom_addr2     <= data_in_d2[18: 5]; // Size = 9. Remove upper 9 bits  
                    4'b1010 : rom_addr2     <= data_in_d2[17: 4]; // Size = 10. Remove upper 10 bits  
                    4'b1011 : rom_addr2     <= data_in_d2[16: 3]; // Size = 11. Remove upper 11 bits  
                    4'b1100 : rom_addr2     <= data_in_d2[15: 2]; // Size = 12. Remove upper 12 bits  
                    4'b1101 : rom_addr2     <= data_in_d2[14: 1]; // Size = 13. Remove upper 13 bits  
                    4'b1110 : rom_addr2     <= data_in_d2[13: 0]; // Size = 14. Remove upper 14 bits  

                    default : rom_addr2     <= 14'bX; 
                endcase;
            end;
        end

    end


    //----------------------------------------------------------------------------------------------------------------------
    // Pipeline registers for dv and channel
    //----------------------------------------------------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin
        if (reset) begin
            flag_no_row1_d1 <= 1'b0;
            flag_no_row1_d2 <= 1'b0;
            flag_no_row1_d3 <= 1'b0;

            flag_no_row2_d1 <= 1'b0;
            flag_no_row2_d2 <= 1'b0;
            flag_no_row2_d3 <= 1'b0;

            data_in_d2      <= 0;

            data_in_dv_d1   <= 1'b0;
            data_in_dv_d2   <= 1'b0;
            data_in_dv_d3   <= 1'b0;
            data_in_dv_d4   <= 1'b0;

            chan_d1         <= 4'b0000;
            chan_d2         <= 4'b0000;
            chan_d3         <= 4'b0000;
            chan_d4         <= 4'b0000;

        end else begin
            flag_no_row1_d1 <= flag_no_row1;
            flag_no_row1_d2 <= flag_no_row1_d1;
            flag_no_row1_d3 <= flag_no_row1_d2;

            flag_no_row2_d1 <= flag_no_row2;
            flag_no_row2_d2 <= flag_no_row2_d1;
            flag_no_row2_d3 <= flag_no_row2_d2;

            data_in_d2      <= data_in_d1;

            data16_d1       <= data_in[15:0];
            data16_d2       <= data16_d1;
            data16_d3       <= data16_d2;
            data16_d4       <= data16_d3;


            data_in_dv_d1   <= data_in_dv;
            data_in_dv_d2   <= data_in_dv_d1;
            data_in_dv_d3   <= data_in_dv_d2;
            data_in_dv_d4   <= data_in_dv_d3;

            chan_d1         <= data_in_chan;
            chan_d2         <= chan_d1;
            chan_d3         <= chan_d2;
            chan_d4         <= chan_d3;

        end

    end


    //----------------------------------------------------------------------------------------------------------------------
    // Pipeline registers for ROM row1 outputs
    //----------------------------------------------------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin
        if (reset) begin
            hit_pat1_d1     <= 8'h00;
            hit_pat1_d2     <= 8'h00;

            hit_size1_d1    <= 8'h00;
            hit_size1_d2    <= 8'h00;

            hit_nbits1_d1   <= 8'h00;
            hit_nbits1_d2   <= 8'h00;

        end else begin

            // Replace ROM outputs for row1 with zeros if there are no bits set
            if (flag_no_row1_d1 == 1'b1) begin
                hit_pat1_d1     <= 0;
                hit_size1_d1    <= 0;
                hit_nbits1_d1   <= 0;
            end else begin
                hit_pat1_d1     <= hit_pat1;
                hit_size1_d1    <= hit_size1;
                hit_nbits1_d1   <= hit_nbits1;
            end

            hit_pat1_d2     <= hit_pat1_d1;
            hit_size1_d2    <= hit_size1_d1;
            hit_nbits1_d2   <= hit_nbits1_d1;

        end

    end


    //----------------------------------------------------------------------------------------------------------------------
    // Combine decoded rows and add number of bits set in each row. Also add encoded lengths.
    // Register output data
    //----------------------------------------------------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin
        if (reset) begin
            hitmap_out      <= 16'b0;  // Decoded hitmap
            hitmap_length   <= 5'b0;   // Actual length of the compressed input hitmap (4 to 30)
            hitmap_nbits    <= 5'b0;   // Number of bits set in the decoded hitmap. (1 to 16)
            hitmap_out_chan <= 4'b0;   // Channel number of output hitmap
            hitmap_out_dv   <= 1'b0;   // Output data valid

        end else begin

            if (data_in_dv_d4 == 1'b1) begin

                if (reg_en_encode == 1'b1) begin

                    if (flag_no_row2_d3 == 1'b1) begin      // No bits set in row2
                        hitmap_out      <= {hit_pat1_d2, 8'b00000000};  
                        hitmap_length   <= hit_size1_d2 + 2; // Add two bits for first node  
                        hitmap_nbits    <= hit_nbits1_d2;      
                    end else begin
                        hitmap_out      <= {hit_pat1_d2, hit_pat2};
                
                        if (flag_no_row1_d3 == 1'b1)       // No bits set in row2, first node is 1-bit
                            hitmap_length   <= hit_size2 + 1;   
                        else
                            hitmap_length   <= hit_size1_d2 + hit_size2 + 2; // Add two bits for first node  
                    
                        hitmap_nbits    <= hit_nbits1_d2 + hit_nbits2;   
                    end

                end else begin                      // No encoding
                    hitmap_out      <= data16_d4;
                    hitmap_length   <= 5'b10000;    // 16
                    hitmap_nbits    <= data16_d4[15] + data16_d4[14] + data16_d4[13] + data16_d4[12]
                                     + data16_d4[11] + data16_d4[10] + data16_d4[ 9] + data16_d4[ 8]
                                     + data16_d4[ 7] + data16_d4[ 6] + data16_d4[ 5] + data16_d4[ 4]
                                     + data16_d4[ 3] + data16_d4[ 2] + data16_d4[ 1] + data16_d4[ 0];      
                end

                hitmap_out_chan <= chan_d4;   
                hitmap_out_dv   <= 1'b1;   

            end else begin
                hitmap_out      <= 16'b0;  
                hitmap_length   <= 5'b0;   
                hitmap_nbits    <= 5'b0;   
                hitmap_out_chan <= 4'b0;   
                hitmap_out_dv   <= 1'b0;   

            end
        end

    end

endmodule

`endif



