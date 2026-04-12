//----------------------------------------------------------------------------------------------------------------------
// [Filename]       hit_barrelshift.sv [RTL]
// [Project]        RD53B pixel ASIC
// [Author]         
// [Language]       SystemVerilog 2012 [IEEE Std. 1800-2012]
// [Created]        
// [Description]    Component of the block that builds 64-bit Aurora output words 
//                  from variable size hit data.
//
//                  Barrel shift the 110-bit input right, into a position in an 
//                  output register that can be read out in 63-bit blocks. 
//                  Bits shifted below bit 0 are wrapped around to
//                  the upper bits. (Right shift with rotation)
//                  This requires the output register to be 4x64 bits so that the 
//                  max 110 bit value can be written without LSBs wrapping around 
//                  into the same word as the MSBs for 2 clock cycles.
//                  The output words are from reg_accum[314:252], [251:189], [188:126], [125:63] and [62:0]
//
//                  Example: A shift of 94 would have din[110:0] shifted to reg_accum[xx:xx]. 
//                  This over-writes bits in three of the 63-bit segments. The segment
//                  from [188:126] is complete, as is the segment [125:63]. Segment [62:0] is not complete.
//                  If there were only three segments then instead of the LSBs written to the third segment [62:51]
//                  they would have wrapped around to the first segment and over-written bits [251:???]
//                    
//                  The required shift is carried out in multiple stages. 
//                  First  stage is a 2:1 mux using din_shift[8]   to select a shift of 0          or 256
//                  Second stage is a 4:1 mux using din_shift[7:6] to select a shift of 0, 64, 128 or 192
//                  Third  stage is a 4:1 mux using din_shift[5:4] to select a shift of 0, 16,  32 or  48
//                  Fourth stage is a 4:1 mux using din_shift[3:2] to select a shift of 0,  4,   8 or  12
//                  Fifth  stage is a 4:1 mux using din_shift[1:0] to select a shift of 0,  1,   2 or   3
//----------------------------------------------------------------------------------------------------------------------
`ifndef HIT_BSHIFT_SV
`define HIT_BSHIFT_SV

`timescale 1ns / 1ps

`default_nettype none

module hit_barrelshift
(
    input   logic           clk             ,
    input   logic           reset           ,

    input   logic  [109:0]  din             ,   // Hit data in MSBs (addr,hitmap,ToTs)
    input   logic   [ 8:0]  din_shift       ,   // Shift input data right, with rotation, by this amount. 0-127
    input   logic           din_eos         ,   // Input data end-of-stream. Pipelined through block.
    input   logic           din_eoe         ,   // Input data end-of-event. Pipelined through block.
    input   logic   [ 8:0]  din_ptr         ,   // Input value of the next free bit in the output once din has been stored. Pipelined through block.
    input   logic           din_dv          ,   // Input data valid.
    
    output  logic  [314:0]  dout            ,   // Output data. 
    output  logic           dout_eos        ,   // Output data end-of-stream.
    output  logic           dout_eoe        ,   // Output data end-of-event.
    output  logic   [ 8:0]  dout_ptr        ,   // Output value of the next free bit in the output once dout has been stored.
    output  logic           dout_dv             // Output data valid
);


    logic  [109:0]  din_d1; // Pipeline register for din while din_shift is being calculated

    // Pipeline registers
    logic   [ 8:0]  sreg_din_dv;
    logic   [ 8:0]  sreg_din_eos;
    logic   [ 8:0]  sreg_din_eoe;
    logic   [ 8:0]  sreg_din_ptr[5:0];

    // Pipeline shift accumulation registers
    logic  [314:0]  reg_accum1, reg_accum2, reg_accum3, reg_accum4, reg_accum5;   

    logic   [ 7:0]  din_shift_d1;
    logic   [ 5:0]  din_shift_d2;
    logic   [ 3:0]  din_shift_d3;
    logic   [ 1:0]  din_shift_d4;


    //--------------------------------------------------------------------------------------
    // Pipeline stages.
    //--------------------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin

        if (reset) begin

            sreg_din_dv     <= 0;
            sreg_din_eos    <= 0;
            sreg_din_eoe    <= 0;
            sreg_din_ptr[0] <= 0;
            sreg_din_ptr[1] <= 0;
            sreg_din_ptr[2] <= 0;
            sreg_din_ptr[3] <= 0;
            sreg_din_ptr[4] <= 0;
            sreg_din_ptr[5] <= 0;

        end else begin

            sreg_din_dv     <= {sreg_din_dv[4:0] , din_dv };
            sreg_din_eos    <= {sreg_din_eos[4:0], din_eos};
            sreg_din_eoe    <= {sreg_din_eoe[4:0], din_eoe};
            sreg_din_ptr    <= {sreg_din_ptr[4:0], din_ptr};

            din_shift_d1    <= din_shift[7:0];
            din_shift_d2    <= din_shift_d1[5:0];
            din_shift_d3    <= din_shift_d2[3:0];
            din_shift_d4    <= din_shift_d3[1:0];


            //------------------------------------------------------
            // Stage1   : Shift 0 or 256
            //------------------------------------------------------
            case (din_shift[8])
                1'b0    : reg_accum1    <= {din      , 205'b0};                     // Shift 0
                1'b1    : reg_accum1    <= {din[50:0], 205'b0, din[109:51] };       // Shift 256
                default : reg_accum1    <= {din[50:0], 205'b0, din[109:51] }; 
            endcase;                                     
                                                        

            //------------------------------------------------------
            // Stage2   : shift 0, 64, 128 or 192
            //------------------------------------------------------
            case (din_shift_d1[7:6])
                2'b00   : reg_accum2    <= {                    reg_accum1[314:  0] };  // Shift 0
                2'b01   : reg_accum2    <= { reg_accum1[ 63:0], reg_accum1[314: 64] }; 
                2'b10   : reg_accum2    <= { reg_accum1[127:0], reg_accum1[314:128] }; 
                2'b11   : reg_accum2    <= { reg_accum1[191:0], reg_accum1[314:192] };  // Shift 192
                default : reg_accum2    <= { reg_accum1[191:0], reg_accum1[314:192] }; 
            endcase;


            //------------------------------------------------------
            // Stage3 
            //  shift of 0, 16,  32 or  48
            //------------------------------------------------------
            case (din_shift_d2[5:4])
                2'b00   : reg_accum3    <= {                    reg_accum2[314:  0] };  // Shift 0
                2'b01   : reg_accum3    <= { reg_accum2[ 15:0], reg_accum2[314: 16] }; 
                2'b10   : reg_accum3    <= { reg_accum2[ 31:0], reg_accum2[314: 32] }; 
                2'b11   : reg_accum3    <= { reg_accum2[ 47:0], reg_accum2[314: 48] };  // Shift 48
                default : reg_accum3    <= { reg_accum2[ 47:0], reg_accum2[314: 48] }; 
            endcase;


            //------------------------------------------------------
            // Stage4   : shift of 0,  4,   8 or  12
            //------------------------------------------------------
            case (din_shift_d3[3:2])
                2'b00   : reg_accum4    <= {                    reg_accum3[314:  0] };  // Shift 0
                2'b01   : reg_accum4    <= { reg_accum3[  3:0], reg_accum3[314:  4] }; 
                2'b10   : reg_accum4    <= { reg_accum3[  7:0], reg_accum3[314:  8] }; 
                2'b11   : reg_accum4    <= { reg_accum3[ 11:0], reg_accum3[314: 12] };  // Shift 12
                default : reg_accum4    <= { reg_accum3[ 11:0], reg_accum3[314: 12] }; 
            endcase;                                                                               
                                                                                  
            //------------------------------------------------------
            // Stage5   : shift of 0,  1,   2 or   3
            //------------------------------------------------------
            case (din_shift_d4[1:0])
                2'b00   : reg_accum5    <= {                    reg_accum4[314:  0] };  // Shift 0
                2'b01   : reg_accum5    <= { reg_accum4[    0], reg_accum4[314:  1] }; 
                2'b10   : reg_accum5    <= { reg_accum4[  1:0], reg_accum4[314:  2] }; 
                2'b11   : reg_accum5    <= { reg_accum4[  2:0], reg_accum4[314:  3] };  // Shift 3
                default : reg_accum5    <= { reg_accum4[  2:0], reg_accum4[314:  3] }; 
            endcase;

        end
        
    end 

    assign  dout        = reg_accum5;
    assign  dout_dv     = sreg_din_dv[4];
    assign  dout_eos    = sreg_din_eos[4];
    assign  dout_eoe    = sreg_din_eoe[4];
    assign  dout_ptr    = sreg_din_ptr[4];


endmodule
    
`endif

