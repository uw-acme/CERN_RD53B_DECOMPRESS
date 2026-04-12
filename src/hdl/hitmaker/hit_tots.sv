//----------------------------------------------------------------------------------------------------------------------
// [Filename]       hit_tots.sv [RTL]
// [Project]        RD53B emulator
// [Author]         
// [Language]       SystemVerilog 2012 [IEEE Std. 1800-2012]
// [Created]        
// [Description]    
//
//----------------------------------------------------------------------------------------------------------------------
`ifndef HIT_TOTS__SV
`define HIT_TOTS__SV

`timescale 1ns / 1ps


//----------------------------------------------------------------------------------------------------------------------------------
module hit_tots
(
    input   logic           clk         ,
    input   logic           reset       ,

    input   logic           en_tot      ,   // '1' = ToT enabled, '0'= No ToT data
    input   logic           mode_tot    ,   // '0' = Constant (tot_value), '1' = Incrementing
    input   logic   [ 3:0]  tot_value   ,   // ToT value for constant mode

    input   logic   [15:0]  din         ,   // Input data, 8x2 hitmap
    input   logic           din_eos     ,   // Input data end-of-stream. Used to flush hits
    input   logic           din_dv      ,   // Input data valid
    
    output  logic   [63:0]  dout        ,   // Output data. Up to 16 4-bit ToT values (in MSBs)
    output  logic   [ 6:0]  dout_size   ,   // Number of bits in dout
    output  logic           dout_eos    ,   // Output data end-of-stream. Can be used to check EOS alignment with addr and ToT encoding blocks
    output  logic           dout_dv         // Output data valid
);

    integer i;
    logic   [ 4:0]  ones;

    // Pipeline regs
    logic   [ 4:0]  ones_d1, ones_d2;
    logic           din_dv_d1, din_dv_d2;
    logic           din_eos_d1, din_eos_d2;
   

    //--------------------------------------------------------------------------------------
    // 4-bit output for each bit set in input data 
    // 3-stage pipeline to match hitmap encoder delay
    // Drive outputs.
    //--------------------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin

        if (reset) begin

            din_dv_d1           <= 1'b0;
            din_dv_d2           <= 1'b0;
            ones_d1             <= 5'b00000;
            ones_d2             <= 5'b00000;
            dout_size           <= 6'b00000; 
            dout                <= 64'h0000000000000000;
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
                // First stage pipeline 
                // Count the number of bits in the input data
                //------------------------------------------------------------------------------
                ones = 5'b0;                // Initialize count variable.

                for (i=0 ; i<16 ; i=i+1)    // For all the bits.
                    ones = ones + din[i];   // Add the bit to the count.

                ones_d1 <= ones;
                din_dv_d1   <= din_dv;


                //------------------------------------------------------------------------------
                // Second stage
                //------------------------------------------------------------------------------
                din_dv_d2   <= din_dv_d1;
                ones_d2     <= ones_d1;


                //------------------------------------------------------------------------------
                // Third stage
                // Output data. 
                //------------------------------------------------------------------------------
                if (en_tot == 1'b0)
                    dout    <= 64'h0000000000000000;
            
                else begin
                    if (mode_tot == 1'b0) begin  // Constant

                        case (ones_d2)
                           16 : dout    <= { 16{tot_value}};   
                           15 : dout    <= {{15{tot_value}},     4'b0000};   
                           14 : dout    <= {{14{tot_value}}, { 2{4'b0000}}};   
                           13 : dout    <= {{13{tot_value}}, { 3{4'b0000}}};   
                           12 : dout    <= {{12{tot_value}}, { 4{4'b0000}}};   
                           11 : dout    <= {{11{tot_value}}, { 5{4'b0000}}};   
                           10 : dout    <= {{10{tot_value}}, { 6{4'b0000}}};   
                            9 : dout    <= {{ 9{tot_value}}, { 7{4'b0000}}};   
                            8 : dout    <= {{ 8{tot_value}}, { 8{4'b0000}}};   
                            7 : dout    <= {{ 7{tot_value}}, { 9{4'b0000}}};   
                            6 : dout    <= {{ 6{tot_value}}, {10{4'b0000}}};   
                            5 : dout    <= {{ 5{tot_value}}, {11{4'b0000}}};   
                            4 : dout    <= {{ 4{tot_value}}, {12{4'b0000}}};   
                            3 : dout    <= {{ 3{tot_value}}, {13{4'b0000}}};   
                            2 : dout    <= {{ 2{tot_value}}, {14{4'b0000}}};   
                            1 : dout    <= {{ 1{tot_value}}, {15{4'b0000}}};   
                            0 : dout    <= {                 {16{4'b0000}}};   
                            default: dout    <= 64'bX;
                        endcase

                    end
            
                    else 
                        dout    <= {4'h0, 4'h1, 4'h2, 4'h3,     // Incrementing
                                    4'h4, 4'h5, 4'h6, 4'h7, 
                                    4'h8, 4'h9, 4'hA, 4'hB, 
                                    4'hC, 4'hD, 4'hE, 4'h0      // 0xF = no hit
                                   }; 
                end

                // Number of bits in ToT output bus
                if (en_tot)
                    dout_size   <= {ones_d2, 2'b00}; 
                else
                    dout_size   <= 6'b000000;                   // No ToT output
        
                // Pipeline delays for data valid
                dout_dv     <= din_dv_d2;
                dout_eos    <= din_eos_d2;

            end else begin
                dout_dv     <= 1'b0;
                dout_eos    <= 1'b0;
                dout        <= 64'h0;
                dout_size   <= 6'b000000; 
            end

        end

    end 

endmodule
    
`endif

