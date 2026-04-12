//----------------------------------------------------------------------------------------------------------------------
// [Filename]       hit_packer.sv [RTL]
// [Project]        RD53B pixel ASIC
// [Author]         
// [Language]       SystemVerilog 2012 [IEEE Std. 1800-2012]
// [Created]        
// [Description]    Pack the address , hitmap and ToT fields into the MSBs of one output bus
//
//----------------------------------------------------------------------------------------------------------------------
`ifndef HIT_PACKER__SV
`define HIT_PACKER__SV

`timescale 1ns / 1ps

module hit_packer
(
    input   logic           clk             ,
    input   logic           reset           ,

    input   logic   [15:0]  din_addr        ,   // Compressed address (in MSBs)
    input   logic   [ 4:0]  din_addr_size   ,   // Number of bits in compressed address

    input   logic   [29:0]  din_hitmap      ,   // Encoded hitmap (in MSBs)
    input   logic   [ 4:0]  din_hitmap_size ,   // Number of bits in encoded hitmap

    input   logic   [63:0]  din_tots        ,   // Up to 16 4-bit ToT values (in MSBs)
    input   logic   [ 6:0]  din_tots_size   ,   // Number of bits in ToT bus

    input   logic           din_eos         ,   // Input data end-of-stream.  Passed through
    input   logic           din_eoe         ,   // Input data end-of-event.  Passed through
    input   logic           din_dv          ,   // Input data valid
    
    output  logic  [109:0]  dout            ,   // Output data. 
    output  logic   [ 6:0]  dout_size       ,   // Number of bits in all hit fields
    output  logic           dout_eos        ,   // Output data end-of-stream
    output  logic           dout_eoe        ,   // Output data end-of-event
    output  logic           dout_dv             // Output data valid
);

    //--------------------------------
    // Field   :   Min   Max 
    //--------------------------------
    // Address :     2    16
    // Hitmap  :     4    30
    // ToT     :     4    64
    //--------------------------------
    // Total   :    10    110
    //--------------------------------


    //--------------------------------------------------------------------------------------
    // Field   MSB possible         LSB possible
    // Addr	    109   		        108, 102, 100, 94	(Field width 2,8,10,16)
    // hitmap	107,101,99,93 	    104 to 64   	    (4 locations for MSB)
    // ToT	    103 to 63		    100 to 0     	    (40 locations for MSB)
    //--------------------------------------------------------------------------------------
    // Addr field (ccol, islast, isneigbor, qrow} has only has 4 possible width values (16,10,8,2) 
    // so the following hitmap MSB can only be in 4 locations.
    // The hitmap size can be any value from 4 to 30, so the ToT MSB has 26 possible loc offsets
    // from each of the 4 hitmap MSBs. 
    // Therefore the ToT MSB can range from hitmap_min = 2 + 26, to hitmap_max 16 + 26 = 14+26 = 40 possible locations.
    //--------------------------------------------------------------------------------------
    // Pipelining
    // First stage  : Addr into accum reg. Shift hitmap to final location. Calc ToT shift. 
    // Second stage : OR hitmap into accum reg. Do shift of ToT to final loc. 
    // Third stage  : OR shifted ToT into accum reg. 
    //--------------------------------------------------------------------------------------

    // Pipeline regs
    logic           din_dv_d1, din_dv_d2;
    logic           din_eos_d1, din_eos_d2;
    logic           din_eoe_d1, din_eoe_d2;
    logic   [15:0]  din_d1;             // For input data delay when not encoding 
    logic   [15:0]  accum_d1;           // for 'din_addr'
    logic   [45:0]  accum_d2;           // For din_addr + din_hitmap (shift_hitmap)
    logic   [63:0]  din_tots_d1;
    logic   [ 6:0]  din_tots_size_d1;

    logic   [ 5:0]  size_addr_hit;      // Combined size 2 to 46
    logic   [43:0]  shifted_hitmap;     // Map hitmap is 30 bits, with 4 offsets (2,8,10,16) = 0,6,8,14 relative        

    // ToT needs a 41:1 shift selection. 
    logic   [ 5:0]  amt_shift_tots;     // 0 to 40
    logic  [103:0]  shifted_tots;
    logic   [13:0]  merge_addr_hitmap;  // Bus to contain 'OR' of accum_d1 (addr) with overlapping bits of shifted hitmap; 
    logic   [39:0]  merge_tots;         // Bus to contain 'OR' of accum_d2 (addr,hitmap) with overlapping bits of shifted ToT values; 
    logic   [ 6:0]  size_all;           // Combined size 10 to 110
    logic           dbg_err_shift_tots;

    //--------------------------------------------------------------------------------------
    // Drive outputs.
    //--------------------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin

        if (reset) begin

            din_dv_d1           <= 1'b0;
            din_dv_d2           <= 1'b0;
            din_eos_d1          <= 1'b0;
            din_eos_d2          <= 1'b0;
            din_tots_d1         <= 0;
            din_tots_size_d1    <= 0;

            shifted_hitmap      <= 0;
            shifted_tots        <= 0;
            amt_shift_tots      <= 0;
            accum_d1            <= 0;
            accum_d2            <= 0;
            merge_addr_hitmap   <= 0;
            merge_tots          <= 0;
            size_addr_hit       <= 0;
            size_all            <= 0;
            dbg_err_shift_tots  <= 1'b0;

            dout                <= 0;
            dout_size           <= 0;
            dout_eos            <= 1'b0;
            dout_dv             <= 1'b0;

        end else begin

            //------------------------------------------------------------------------------
            // First stage pipeline 
            // Addr into accum reg. Shift hitmap to final location. 
            // Calc ToT shift. 
            //------------------------------------------------------------------------------
            din_dv_d1       <= din_dv;
            din_eos_d1      <= din_eos;
            din_eoe_d1      <= din_eoe;
            accum_d1        <= din_addr;

            case (din_addr_size)
                    2   :   shifted_hitmap  <= {din_hitmap, 14'b00000000000000};      // 30 bits in MSB of bus, 14 padding zeros
                    8   :   shifted_hitmap  <= {6'b000000, din_hitmap, 8'b00000000};  // 30 bits, 14 padding zeros
                   10   :   shifted_hitmap  <= {8'b00000000, din_hitmap, 6'b000000};  // 30 bits, 14 padding zeros
                   16   :   shifted_hitmap  <= {14'b00000000000000, din_hitmap};      // 30 bits in LSB of bus, 14 zeros
                default :   shifted_hitmap  <= 0;
            endcase

            // Shift amount for ToT field
            amt_shift_tots  <= din_addr_size + din_hitmap_size - 6;    // ToT shift is 0 to 40
            size_addr_hit   <= din_addr_size + din_hitmap_size;

            din_tots_d1     <= din_tots;
            din_tots_size_d1 <= din_tots_size;


            //------------------------------------------------------------------------------
            // Second stage
            //------------------------------------------------------------------------------
            merge_addr_hitmap   = accum_d1[13:0] | shifted_hitmap[43:30]; 
            accum_d2            <= {accum_d1[15:14], merge_addr_hitmap, shifted_hitmap[29:0]};

            case (amt_shift_tots)
                     0   :   shifted_tots    <= {       din_tots_d1,  40'b0 };      // 64 bits in MSB of bus, 40 LSBs zero
                     1   :   shifted_tots    <= { 1'b0, din_tots_d1,  39'b0 };      // 
                     2   :   shifted_tots    <= { 2'b0, din_tots_d1,  38'b0 };      // 
                     3   :   shifted_tots    <= { 3'b0, din_tots_d1,  37'b0 };      //
                     4   :   shifted_tots    <= { 4'b0, din_tots_d1,  36'b0 };      //
                     5   :   shifted_tots    <= { 5'b0, din_tots_d1,  35'b0 };      //
                     6   :   shifted_tots    <= { 6'b0, din_tots_d1,  34'b0 };      //
                     7   :   shifted_tots    <= { 7'b0, din_tots_d1,  33'b0 };      //
                     8   :   shifted_tots    <= { 8'b0, din_tots_d1,  32'b0 };      //
                     9   :   shifted_tots    <= { 9'b0, din_tots_d1,  31'b0 };      //
                    10   :   shifted_tots    <= {10'b0, din_tots_d1,  30'b0 };      //
                    11   :   shifted_tots    <= {11'b0, din_tots_d1,  29'b0 };      //
                    12   :   shifted_tots    <= {12'b0, din_tots_d1,  28'b0 };      //
                    13   :   shifted_tots    <= {13'b0, din_tots_d1,  27'b0 };      //
                    14   :   shifted_tots    <= {14'b0, din_tots_d1,  26'b0 };      //
                    15   :   shifted_tots    <= {15'b0, din_tots_d1,  25'b0 };      //
                    16   :   shifted_tots    <= {16'b0, din_tots_d1,  24'b0 };      //
                    17   :   shifted_tots    <= {17'b0, din_tots_d1,  23'b0 };      //
                    18   :   shifted_tots    <= {18'b0, din_tots_d1,  22'b0 };      //
                    19   :   shifted_tots    <= {19'b0, din_tots_d1,  21'b0 };      //
                    20   :   shifted_tots    <= {20'b0, din_tots_d1,  20'b0 };      //
                    21   :   shifted_tots    <= {21'b0, din_tots_d1,  19'b0 };      //
                    22   :   shifted_tots    <= {22'b0, din_tots_d1,  18'b0 };      //
                    23   :   shifted_tots    <= {23'b0, din_tots_d1,  17'b0 };      //
                    24   :   shifted_tots    <= {24'b0, din_tots_d1,  16'b0 };      //
                    25   :   shifted_tots    <= {25'b0, din_tots_d1,  15'b0 };      //
                    26   :   shifted_tots    <= {26'b0, din_tots_d1,  14'b0 };      //
                    27   :   shifted_tots    <= {27'b0, din_tots_d1,  13'b0 };      //
                    28   :   shifted_tots    <= {28'b0, din_tots_d1,  12'b0 };      //
                    29   :   shifted_tots    <= {29'b0, din_tots_d1,  11'b0 };      //
                    30   :   shifted_tots    <= {30'b0, din_tots_d1,  10'b0 };      //
                    31   :   shifted_tots    <= {31'b0, din_tots_d1,   9'b0 };      //
                    32   :   shifted_tots    <= {32'b0, din_tots_d1,   8'b0 };      //
                    33   :   shifted_tots    <= {33'b0, din_tots_d1,   7'b0 };      //
                    34   :   shifted_tots    <= {34'b0, din_tots_d1,   6'b0 };      //
                    35   :   shifted_tots    <= {35'b0, din_tots_d1,   5'b0 };      //
                    36   :   shifted_tots    <= {36'b0, din_tots_d1,   4'b0 };      //
                    37   :   shifted_tots    <= {37'b0, din_tots_d1,   3'b0 };      //
                    38   :   shifted_tots    <= {38'b0, din_tots_d1,   2'b0 };      //
                    39   :   shifted_tots    <= {39'b0, din_tots_d1,   1'b0 };      //
                    40   :   shifted_tots    <= {40'b0, din_tots_d1         };      // ToTs in LSB

                default  :   begin
                                    shifted_tots        <= 104'bZ; 
                                    dbg_err_shift_tots  <= 1'b1; 
                             end 
            endcase

            // Pipeline delays for data valid and eos
            size_all        <= din_tots_size_d1 + size_addr_hit;
            din_dv_d2       <= din_dv_d1;
            din_eos_d2      <= din_eos_d1;
            din_eoe_d2      <= din_eoe_d1;


            //------------------------------------------------------------------------------
            // Third stage
            // Merge ToT into output data. 
            //------------------------------------------------------------------------------
            merge_tots  = accum_d2[39:0] | shifted_tots[103:64]; 
            dout        <= {accum_d2[45:40], merge_tots, shifted_tots[63:0]};
            dout_size   <= size_all;
        
            // Pipeline delays for data valid and eos, eoe
            dout_dv     <= din_dv_d2;
            dout_eos    <= din_eos_d2;
            dout_eoe    <= din_eoe_d2;
       
        end

    end 

endmodule
    
`endif

