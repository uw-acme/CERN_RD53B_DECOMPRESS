//----------------------------------------------------------------------------
// hit_checker. 
//
// Stores generated hit data in a FIFO. Reads it out and 
// compares expected value agains actual decoded value.
// Expected ToT is made from tot mode register controls and 
// expected hitmap size.
//-----------------------------------------------------------
// dout_err bits
//-----------------------------------------------------------
// Bit    Failure type
//  0        chip_id
//  1        tag
//  2        qrow
//  3        ccol
//  4        hitmap
//  5        ToT
//  6        EOS
//  7        EOE
//----------------------------------------------------------------------------
`timescale 1ns / 1ps

//`include "defines_rd53b.sv"

module hit_checker
(
    input   logic           clk            ,  
    input   logic           reset          ,  
    input   logic           restart        ,   // Initialize tag calculation, clear error counters 

    // Register setup. Operating mode
    input   logic           reg_en_tot      ,  // '1' = ToT enabled, '0'= No ToT data
    input   logic           reg_mode_tot    ,  // '0' = Constant (tot_value), '1' = Incrementing
    input   logic   [ 3:0]  reg_tot_value   ,  // ToT value for constant mode
    input   logic   [ 7:0]  reg_tag_init    ,  // Tag to start output stream. Subsequent tags (internal) will be 11-bit
    input   logic   [ 1:0]  reg_chip_id     ,  //  
    input   logic           reg_en_chip_id  ,  // Enable chip ID[1:0]
    input   logic           reg_en_eos      ,  // Enable min 6 zeros output to mark end of stream
    output  logic   [ 7:0]  status          , 

    // Expected data from hitmaker
    input   logic           exp_eos         ,  
    input   logic           exp_eoe         , 
    input   logic   [ 7:0]  exp_qrow        , 
    input   logic   [ 5:0]  exp_ccol        , 
    input   logic   [15:0]  exp_hitmap      , 
    input   logic           exp_dv          ,  // Expected data valid

    input   logic   [63:0]  exp_tot         ,  // ToT data packed into MSBs of bus
    input   logic   [ 6:0]  exp_tot_size   ,
    input   logic           exp_tot_dv      ,  // Expected ToT data valid. ToT data is delayed from other expected data.

    // Actual data from decoder 
    input   logic   [ 1:0]  act_chip_id     ,  // Current chip_id            
    input   logic   [ 7:0]  act_tag         ,  // Current tag            
    input   logic           act_eos         ,  // End-of-stream            
    input   logic           act_eoe         ,  // End-of-event    Used to check incrementing tag
    input   logic   [ 7:0]  act_qrow        , 
    input   logic   [ 5:0]  act_ccol        , 
    input   logic   [15:0]  act_hitmap      , 
    input   logic   [63:0]  act_tot         ,  // ToT data packed into MSBs of bus
    input   logic           act_dv          ,  // Data valid           

    // Error reporting interface
    output  logic           dout_err_dv     ,  // result valid
    output  logic   [ 7:0]  dout_errs       ,  // error bus [7:0]
    output  logic   [ 7:0]  dout_err_count  ,  // result error count [7:0]

    // Ready signal to prevent overflow
    output logic            ready_out          // Prevents overflow of expected data
);


    // Expected data FIFO I/O signals
    logic   [31:0]  fexp_din, fexp_dout;      
    logic   [ 9:0]  fexp_level;
    logic           fexp_wr,  fexp_rd,  fexp_full, fexp_empty, fexp_overflow, fexp_underflow;

    // Expected ToT data FIFO I/O signals
    logic   [63:0]  ftot_din, ftot_dout; 
    logic   [31:0]  ftot_size_din, ftot_size_dout;     
    logic   [ 9:0]  ftot0_level, ftot1_level, ftot_size_level;
    logic           ftot_wr,  ftot_rd;
    logic           ftot0_full, ftot0_empty, ftot0_underflow, ftot0_overflow;
    logic           ftot1_full, ftot1_empty, ftot1_underflow, ftot1_overflow;
    logic           ftot_size_full, ftot_size_empty, ftot_size_underflow, ftot_size_overflow;
    
    // FIFO output data fields
    logic           fout_exp_eos         ;  
    logic           fout_exp_eoe         ; 
    logic   [ 7:0]  fout_exp_qrow        ; 
    logic   [ 5:0]  fout_exp_ccol        ; 
    logic   [15:0]  fout_exp_hitmap      ; 
    logic           fout_exp_tot         ;

    logic   [ 7:0]  tag_calc             ;  // Tag value, incremented at every 'expected EOE'

    // Pipeline registers for actual data
    logic   [ 1:0]  act_chip_id_d1  ;  // Current chip_id            
    logic   [ 7:0]  act_tag_d1      ;  // Current tag            
    logic           act_eos_d1      ;  // End-of-stream            
    logic           act_eoe_d1      ;  // End-of-event    Used to check incrementing tag
    logic   [ 7:0]  act_qrow_d1     ; 
    logic   [ 5:0]  act_ccol_d1     ; 
    logic   [15:0]  act_hitmap_d1   ; 
    logic   [63:0]  act_tot_d1      ;  // ToT data packed into MSBs of bus
    logic           act_dv_d1       ;  // Data valid       

    //-----------------------------------------------------------
    // Bit in err bus
    //-----------------------------------------------------------
    //                                Bit  Failure type 
    //-----------------------------------------------------------
    logic           err_chip_id;   //  0   chip_id 
    logic           err_tag;       //  1   tag
    logic           err_qrow;      //  2   qrow
    logic           err_ccol;      //  3   ccol
    logic           err_hitmap;    //  4   hitmap
    logic           err_tot;       //  5   ToT
    logic           err_eos;       //  6   EOS
    logic           err_eoe;       //  7   EOE


    // TODO Add logic
    assign  err_eoe = 1'b0;
  //assign  err_eos = 1'b0;

    assign  dout_errs   = {err_eoe, err_eos, err_tot, err_hitmap, err_ccol, err_qrow, err_tag, err_chip_id};
  //assign  dout_errs   = {1'b0   , err_eos, err_tot, err_hitmap, err_ccol, err_qrow, 1'b0   , 1'b0       };


    //----------------------------------------------------------------------------
    // Write expected data into FIFO. 32 bits
    // exp_eos        1-bit
    // exp_eoe        1-bit
    // exp_qrow       8-bit
    // exp_ccol       6-bit
    // exp_hitmap    16-bit 
    //----------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin: pr_fifos_wr
        
        if (reset) begin

            fexp_din    <= 0;
            fexp_wr     <= 1'b0;
            
            ftot_din    <= 0;
            ftot_size_din   <= 0;
            ftot_wr     <= 1'b0;
            
        end else begin

            fexp_din    <= {exp_eos, exp_eoe, exp_qrow, exp_ccol, exp_hitmap};
            fexp_wr     <= exp_dv;

            ftot_din    <= exp_tot;
            ftot_size_din   <= {25'b0, exp_tot_size};
            ftot_wr     <= exp_tot_dv;
        end

    end


    //----------------------------------------------------------------------------
    // Pipeline registers for actual data
    //----------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin: pr_pipe_exp

        if (reset) begin

            act_chip_id_d1  <= 0;
            act_tag_d1      <= 0;
            act_eos_d1      <= 1'b0;
            act_eoe_d1      <= 1'b0;
            act_qrow_d1     <= 0;
            act_ccol_d1     <= 0;
            act_hitmap_d1   <= 0;
            act_tot_d1      <= 0;
            act_dv_d1       <= 1'b0;

        end else begin

            act_chip_id_d1  <= act_chip_id;
            act_tag_d1      <= act_tag    ;
            act_eos_d1      <= act_eos    ;
            act_eoe_d1      <= act_eoe    ;
            act_qrow_d1     <= act_qrow   ;
            act_ccol_d1     <= act_ccol   ;
            act_hitmap_d1   <= act_hitmap ;
            act_tot_d1      <= act_tot    ;
            act_dv_d1       <= act_dv     ;

        end

    end


    //----------------------------------------------------------------------------
    // FIFOs to store expected data until it is needed for comparison with actual
    // decoded data. 
    // FIFO depth must be greater than total encode-decode pipeline delay.
    // ToT FIFO is separate from other expected data because ToT expected data 
    // arrives from hitmaker a few cycles after the other data.
    // All FIFOs are read at the same time.
    //----------------------------------------------------------------------------
    fifo_chk_512x32b    u_fifo_exp         // Block RAM 512x32bit
    (
        .clk        ( clk              ),  // input  wire 
        .srst       ( reset            ),  // input  wire 
        .din        ( fexp_din         ),  // input  wire [31:0] 
        .wr_en      ( fexp_wr          ),  // input  wire 
        .rd_en      ( fexp_rd          ),  // input  wire
        .dout       ( fexp_dout        ),  // output wire [31:0]
        .full       ( fexp_full        ),  // output wire
        .empty      ( fexp_empty       ),  // output wire
        .overflow   ( fexp_overflow    ),  // output wire
        .underflow  ( fexp_underflow   ),  // output wire
        .data_count ( fexp_level       )   // output wire [9:0]
    );

    fifo_chk_512x32b    u_fifo_tot0        // Block RAM 512x32bit for LSBs of ToT
    (
        .clk        ( clk              ),  // input  wire 
        .srst       ( reset            ),  // input  wire 
        .din        ( ftot_din[31:0]   ),  // input  wire [31:0] 
        .wr_en      ( ftot_wr          ),  // input  wire 
        .rd_en      ( ftot_rd          ),  // input  wire
        .dout       ( ftot_dout[31:0]  ),  // output wire [31:0]
        .full       ( ftot0_full       ),  // output wire
        .empty      ( ftot0_empty      ),  // output wire
        .overflow   ( ftot0_overflow   ),  // output wire
        .underflow  ( ftot0_underflow  ),  // output wire
        .data_count ( ftot0_level      )   // output wire [9:0]
    );

    fifo_chk_512x32b    u_fifo_tot1        // Block RAM 512x32bit for MSBs of ToT
    (
        .clk        ( clk              ),  // input  wire 
        .srst       ( reset            ),  // input  wire 
        .din        ( ftot_din[63:32]  ),  // input  wire [31:0] 
        .wr_en      ( ftot_wr          ),  // input  wire 
        .rd_en      ( ftot_rd          ),  // input  wire
        .dout       ( ftot_dout[63:32] ),  // output wire [31:0]
        .full       ( ftot1_full       ),  // output wire
        .empty      ( ftot1_empty      ),  // output wire
        .overflow   ( ftot1_overflow   ),  // output wire
        .underflow  ( ftot1_underflow  ),  // output wire
        .data_count ( ftot1_level      )   // output wire [9:0]
    );
    
    fifo_chk_512x32b    u_fifo_tot_size         // Block RAM 512x32bit
    (
        .clk        ( clk                   ),  // input  wire 
        .srst       ( reset                 ),  // input  wire 
        .din        ( ftot_size_din         ),  // input  wire [31:0] 
        .wr_en      ( ftot_wr               ),  // input  wire 
        .rd_en      ( ftot_rd               ),  // input  wire
        .dout       ( ftot_size_dout        ),  // output wire [31:0]
        .full       ( ftot_size_full        ),  // output wire
        .empty      ( ftot_size_empty       ),  // output wire
        .overflow   ( ftot_size_overflow    ),  // output wire
        .underflow  ( ftot_size_underflow   ),  // output wire
        .data_count ( ftot_size_level       )   // output wire [9:0]
    );
    
    
    //----------------------------------------------------------------------------
    // Set 'ready_out' low when FIFO level is too high
    //----------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin : pr_ready_out

        if (reset == 1'b1) begin
            ready_out  <= 1'b0;

        end else begin

            if (fexp_level > 10'd256) begin
                ready_out   <= 1'b0;
            end else begin
                ready_out   <= 1'b1;
            end

        end

    end

    assign  status      = {fexp_full,  fexp_empty,  fexp_overflow,  fexp_underflow, 
                           ftot0_full, ftot0_empty, ftot0_overflow, ftot0_underflow};

    // Read all FIFOs
    assign  fexp_rd = act_dv_d1;
    assign  ftot_rd = act_dv_d1;

    assign  dout_err_dv     = 1'b0;
    assign  dout_err_count  = 8'b0;


    // Extract fields from expected-data-FIFO
    assign  fout_exp_eos    = fexp_dout[31]     ; //        
    assign  fout_exp_eoe    = fexp_dout[30]     ; //       
    assign  fout_exp_qrow   = fexp_dout[29:22]  ; //[ 7:0] 
    assign  fout_exp_ccol   = fexp_dout[21:16]  ; //[ 5:0] 
    assign  fout_exp_hitmap = fexp_dout[15: 0]  ; //[15:0] 
    
    assign  fout_exp_tot    = ftot_dout;


    //----------------------------------------------------------------------------
    // Check chip_id against input setup value
    //----------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin : pr_err_chip_id

        if (reset == 1'b1) begin
            err_chip_id <= 1'b0;

        end else begin

            if ((act_dv_d1 == 1'b1) & (act_chip_id_d1 != reg_chip_id)) begin
                err_chip_id <= 1'b1;
                $display("**** Chip_id is exp: %d, act: %d", reg_chip_id, act_chip_id_d1);
            end else begin
                err_chip_id <= 1'b0;
            end

        end

    end


    //----------------------------------------------------------------------------
    // Check tags against initially setup tag + incremented tag
    //----------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin : pr_err_tag

        if ((reset == 1'b1) | (restart == 1'b1)) begin
            err_tag     <= 1'b0;
            tag_calc    <= reg_tag_init;

        end else begin

            // Error check (every word) 
            if ((act_dv_d1 == 1'b1) & (act_tag_d1 != tag_calc)) begin
                err_tag     <= 1'b0;
                //err_tag     <= 1'b1;
                //$display("**** Tag is exp: %d, act: %d", tag_calc, act_tag_d1);
            end else begin
                err_tag     <= 1'b0;
            end

            // Update tag at EOE
            if ((act_dv_d1 == 1'b1) & (fout_exp_eoe == 1'b1)) begin
                tag_calc    <= tag_calc + 1;
            end

        end

    end
    

    //----------------------------------------------------------------------------
    // Check actual ccol, qrow against expected values
    //----------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin : pr_err_addr

        if (reset == 1'b1) begin
            err_ccol    <= 1'b0;
            err_qrow    <= 1'b0;

        end else begin

            if ((act_dv_d1 == 1'b1) & (act_ccol_d1 != fout_exp_ccol)) begin
                err_ccol    <= 1'b1;
                $display("**** Ccol is exp: %d, act: %d", fout_exp_ccol, act_ccol_d1);
            end else begin
                err_ccol    <= 1'b0;
            end

            if ((act_dv_d1 == 1'b1) & (act_qrow_d1 != fout_exp_qrow)) begin
                err_qrow    <= 1'b1;
                $display("\n**** Qrow error exp: %d, act: %d", fout_exp_qrow, act_qrow_d1); 
            end else begin
                err_qrow    <= 1'b0;
            end

        end

    end

    
    //----------------------------------------------------------------------------
    // Check EOS expected values
    //----------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin : pr_err_eos

        if (reset == 1'b1) begin
            err_eos     <= 1'b0;

        end else begin

            if ((act_dv_d1 == 1'b1) & (act_eos_d1 != fout_exp_eos)) begin
                err_eos     <= 1'b1;
                $display("\n**** EOS is exp: %d, act: %d", fout_exp_eos, act_eos_d1);
            end else begin
                err_eos     <= 1'b0;
            end

        end

    end


    //----------------------------------------------------------------------------
    // Check actual hitmap against expected
    //----------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin : pr_err_hitmap

        if (reset == 1'b1) begin
            err_hitmap  <= 1'b0;

        end else begin

            if ((act_dv_d1 == 1'b1) & (act_hitmap_d1 != fout_exp_hitmap)) begin
                $display("**** Hitmap is exp: %X, act: %X \n", fout_exp_hitmap, act_hitmap_d1);    
                err_hitmap  <= 1'b1;
            end else begin
                err_hitmap  <= 1'b0;
            end

        end

    end

    //----------------------------------------------------------------------------
    // Check actual ToTs against values calculated from hitmap bits and setup 
    // values in reg_mode_tot and reg_tot_value.
    // Checking is disabled if reg_en_tot = 0
    //----------------------------------------------------------------------------
    integer i;

    logic [63:0] tot_mask;
    logic [63:0] act_tot_d1_masked;
    logic [63:0] exp_tot_d1_masked;
    always_comb begin
        tot_mask = {64{1'b1}} << (32'd64 - ftot_size_dout);
        act_tot_d1_masked = tot_mask & act_tot_d1;
        exp_tot_d1_masked = tot_mask & ftot_dout;
    end

    always_ff @(posedge clk) 
    begin : pr_err_tot

        if (reset == 1'b1) begin
            err_tot     <= 1'b0;

        end else begin

            if ((act_dv_d1 == 1'b1) & (reg_en_tot == 1'b1))begin
                if (act_tot_d1_masked != exp_tot_d1_masked) begin
                        err_tot <= 1'b1; 
                        $display("**** ToT is exp: %X, act: %X \n", ftot_dout, act_tot_d1); 
                end
            end else begin
                err_tot <= 1'b0;
            end
        end
    end
 
    
    
//    //----------------------------------------------------------------------------
//    //  Debug hardware to capture the first error in the system 
//    //
//    //  ILA to look at signals while hardware testing
//    //----------------------------------------------------------------------------
//
//        hit_checker_ila u_hit_checker_ila (
//            .clk(clk), // input wire clk
//
//
//            .probe0(err_ccol), // input wire [0:0]  probe0  
//            .probe1(err_qrow), // input wire [0:0]  probe1 
//            .probe2(err_hitmap), // input wire [0:0]  probe2 
//            .probe3(fout_exp_ccol), // input wire [5:0]  probe3 
//            .probe4(act_ccol_d1), // input wire [5:0]  probe4 
//            .probe5(fout_exp_qrow), // input wire [7:0]  probe5 
//            .probe6(act_qrow_d1), // input wire [7:0]  probe6 
//            .probe7(fout_exp_hitmap), // input wire [15:0]  probe7 
//            .probe8(act_hitmap_d1) // input wire [15:0]  probe8
//        );
//
endmodule

