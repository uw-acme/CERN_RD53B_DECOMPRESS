//----------------------------------------------------------------------------------------------------------------------
// [Filename]       hit_encode.sv [RTL]
// [Project]        RD53B pixel ASIC
// [Author]         
// [Language]       SystemVerilog 2012 [IEEE Std. 1800-2012]
// [Created]        
// [Description]    
//
//--------------------------------------------------------------------------------------
// We are processing a 2x8 region of pixels
//
// Hit locations:
//  |----|----|----|----|----|----|----|----|
//  |  0 |  1 |  2 |  3 |  4 |  5 |  6 |  7 | Row 0 -> enc8_dout0
//  |----|----|----|----|----|----|----|----|
//  |  8 |  9 | 10 | 11 | 12 | 13 | 14 | 15 | Row 1 -> enc8_dout1
//  |----|----|----|----|----|----|----|----|
//
//--------------------------------------------------------------------------------------
// To encode a region (2x8 Pixels):
// We first use enc_2bit() to encode the 'OR' of all the bits in the first row and the second row
// and then use two enc_8x1() blocks to encode the upper row the lower row.
// enc_2bit() has 2 'rowhit' inputs and produces the one or two MSBs of the output.
// The two enc_8x1 blocks each take 8 hit inputs for each row and produce 0 to 14 encoded bits
// and the number of bits in the encoded result. 
// All three encoded fields are then packet into one 30-bit output.
// Maximum length of encoded output is 30 bits
//----------------------------------------------------------------------------------------------------------------------
`ifndef HIT_ENCODE__SV
`define HIT_ENCODE__SV

`timescale 1ns / 1ps


module hit_encode
(
    input   logic           clk         ,
    input   logic           reset       ,
    input   logic           en_encode   ,   // '1' = Encode (Compress) din. '0' = dout is din, dout_size = 16 (5'b1000)

    input   logic   [15:0]  din         ,   // Input data, 8x2 hitmap
    input   logic           din_eos     ,   // Input data end-of-stream. Used to flush hits
    input   logic           din_dv      ,   // Input data valid
    
    output  logic   [29:0]  dout        ,   // Output data. Encoded hitmap (in MSBs)
    output  logic   [ 4:0]  dout_size   ,   // Number of bits in encoded hitmap
    output  logic           dout_eos    ,   // Output data end-of-stream. Can be used to check EOS alignment with addr and ToT encoding blocks
    output  logic           dout_dv         // Output data valid
);

    // One bit is set for each row if a row contains any hit bits
    logic   [ 1:0]  hit_rows;

    // 8-bit signals to hold the din bits from each row separately
    logic   [ 7:0]  row0hits, row1hits;

    // Outputs from 2 enc_8x1 blocks
    logic   [13:0]  enc8_dout0;       // Binary Tree Encoded data of the 8 bits from left to right
    logic   [13:0]  enc8_dout1;      
    logic   [ 3:0]  enc8_dout0_size;  // Ranges from 0 (no data) to 14
    logic   [ 3:0]  enc8_dout1_size;  

    // Output from enc2x1
    logic   [ 1:0]  enc2_dout;       
    logic   [ 1:0]  enc2_dout_size; 

    logic   [27:0]  shift_enc8_douts; 

    // Pipeline regs
    logic           din_dv_d1, din_dv_d2;
    logic   [15:0]  din_d1, din_d2;     // For input data delay when not encoding 
    logic   [ 1:0]  enc2_dout_d2;       
    logic   [ 1:0]  enc2_dout_size_d2;
    logic   [13:0]  enc8_dout0_size_d2, enc8_dout1_size_d2;
    logic           din_eos_d1, din_eos_d2;

    assign  hit_rows = { |din[7:0], |din[15:8] };
    assign  row0hits = {din[0], din[1], din[2] , din[3] , din[4] , din[5] , din[6] , din[7] };
    assign  row1hits = {din[8], din[9], din[10], din[11], din[12], din[13], din[14], din[15]};
   

    //--------------------------------------------------------------------------------------
    // Encode the 'or' of bits in Row0 (upper) and Row1 (lower)
    //--------------------------------------------------------------------------------------
    enc_2bit u_enc_2bit 
    (
        .clk        ( clk               ),
        .din        ( hit_rows          ),
        .din_dv     ( din_dv            ),
        .dout       ( enc2_dout         ),
        .dout_size  ( enc2_dout_size    )
    );

    //--------------------------------------------------------------------------------------
    // Encode Data words belonging to Row0 and Row1
    //--------------------------------------------------------------------------------------
    enc_8x1 u_enc_8x1_0   
    (
        .clk        ( clk               ), 
        .din        ( row0hits          ), 
        .din_dv     ( din_dv            ),
        .dout       ( enc8_dout0        ), 
        .dout_size  ( enc8_dout0_size   )
    );
    
    enc_8x1 u_enc_8x1_1   
    (
        .clk        ( clk               ), 
        .din        ( row1hits          ), 
        .din_dv     ( din_dv            ),
        .dout       ( enc8_dout1        ), 
        .dout_size  ( enc8_dout1_size   )
    );


    //--------------------------------------------------------------------------------------
    // Drive outputs.
    // Matching 2 stage pipeline delay for din_dv to create dout_dv
    //--------------------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin


        if (reset) begin

            din_dv_d1           <= 1'b0;
            din_d1              <= 0;
            enc2_dout_d2        <= 0;
            enc2_dout_size_d2   <= 0;
            enc8_dout0_size_d2  <= 0;
            enc8_dout1_size_d2  <= 0;
            din_dv_d2           <= 1'b0;
            din_d2              <= 0;
            dout_size           <= 5'b00000; 
            dout                <= 16'h0000;
            dout_dv             <= 1'b0;

        end else begin

            din_eos_d1  <= din_eos & din_dv;
            din_eos_d2  <= din_eos_d1;
        
            //------------------------------------------------------------------------------
            // Advance pipeline on 'din_dv' and also generate two internal pipe shifts after
            // a 'din_eos' to flush the pipeline.
            //------------------------------------------------------------------------------
            if (din_dv | din_eos_d1 | din_eos_d2) begin    
        
                //------------------------------------------------------------------------------
                // First stage pipeline is in enc_2bit and enc_8x1 blocks
                //------------------------------------------------------------------------------
                din_d1      <= din;     // Pipeline input if encoding is not enabled
                din_dv_d1   <= din_dv;


                //------------------------------------------------------------------------------
                // Second stage
                // Combine 8-bit encoded outputs. Pack into MSBs
                //------------------------------------------------------------------------------
                case (enc8_dout0_size)
                     0  : begin shift_enc8_douts <= {                   enc8_dout1, 14'b00000000000000}; end    // enc8_dout0_size is zero
                     1  : begin shift_enc8_douts <= {enc8_dout0[13]   , enc8_dout1, 13'b0000000000000}; end
                     2  : begin shift_enc8_douts <= {enc8_dout0[13:12], enc8_dout1, 12'b000000000000}; end
                     3  : begin shift_enc8_douts <= {enc8_dout0[13:11], enc8_dout1, 11'b00000000000}; end
                     4  : begin shift_enc8_douts <= {enc8_dout0[13:10], enc8_dout1, 10'b0000000000}; end
                     5  : begin shift_enc8_douts <= {enc8_dout0[13: 9], enc8_dout1,  9'b000000000}; end
                     6  : begin shift_enc8_douts <= {enc8_dout0[13: 8], enc8_dout1,  8'b00000000}; end
                     7  : begin shift_enc8_douts <= {enc8_dout0[13: 7], enc8_dout1,  7'b0000000}; end
                     8  : begin shift_enc8_douts <= {enc8_dout0[13: 6], enc8_dout1,  6'b000000}; end
                     9  : begin shift_enc8_douts <= {enc8_dout0[13: 5], enc8_dout1,  5'b00000}; end
                    10  : begin shift_enc8_douts <= {enc8_dout0[13: 4], enc8_dout1,  4'b0000}; end
                    11  : begin shift_enc8_douts <= {enc8_dout0[13: 3], enc8_dout1,  3'b000}; end
                    12  : begin shift_enc8_douts <= {enc8_dout0[13: 2], enc8_dout1,  2'b00}; end
                    13  : begin shift_enc8_douts <= {enc8_dout0[13: 1], enc8_dout1,  1'b0}; end
                    14  : begin shift_enc8_douts <= {enc8_dout0[13: 0], enc8_dout1      }; end
                    
                    default : begin shift_enc8_douts <= {               enc8_dout1, 14'b00000000000000}; end
                endcase
        
                enc2_dout_d2        <= enc2_dout;
                enc2_dout_size_d2   <= enc2_dout_size;
                enc8_dout0_size_d2  <= enc8_dout0_size;
                enc8_dout1_size_d2  <= enc8_dout1_size;
                din_dv_d2           <= din_dv_d1;
                din_d2              <= din_d1;


                //------------------------------------------------------------------------------
                // Third stage
                // Output data. Encoded hitmap (in MSBs)
                //------------------------------------------------------------------------------
                if      (en_encode == 1'b0)         // Encoding turned off
                    dout    <= din_d2;   
                else if (enc2_dout_size_d2 == 1)    // Compression of "01" to a single "0"
                    dout    <= {enc2_dout_d2[1], shift_enc8_douts, 1'b0}; // enc2_dout_d2[1] could be replaced with 1b'0 
                else // 2
                    dout    <= {enc2_dout_d2, shift_enc8_douts}; 
        

                // Number of bits in final encoded hitmap
                if (en_encode)
                    dout_size   <= enc2_dout_size_d2 + enc8_dout0_size_d2 + enc8_dout1_size_d2;  
                else
                    dout_size   <= 5'b10000;    // 16 bit output for uncompressed data
        
                // Pipeline delays for data valid
                dout_dv     <= din_dv_d2;
                dout_eos    <= din_eos_d2;
           
            end else begin
                dout_dv     <= 1'b0;
                dout_eos    <= 1'b0;
                dout        <= 64'h0;
                dout_size   <= 5'b00000;    // 16 bit output for uncompressed data
            end
        end

    end 

endmodule
    
`endif
