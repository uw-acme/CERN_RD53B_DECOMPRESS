//----------------------------------------------------------------------------------------------------------------------
// [Filename]       hit_assembler.sv [RTL]
// [Project]        RD53B pixel ASIC
// [Author]         
// [Language]       SystemVerilog 2012 [IEEE Std. 1800-2012]
// [Created]        
// [Description]    Build 64-bit Aurora output words from variable size hit data.
//                  Add 'NS' (new stream) flags, chip ID, increment tag number.
//                  Insert orphan bits at end-of-stream. 
//                  Generate internal tag if column address wraps to 1 (meaning that
//                  the data is from a new event)
//
//                  Input data (16-110 bits), together with the word size are buffered in a FIFO.
//                  A state machine reads the FIFO and sends the data to a 315-bit barrel shifter. 
//                  The shifter is pipelined with either 8 2:1 stages or 4 4:1 stages.
//                  The shifter output is OR'ed with a 315-bit accumulator register composed of 5 63-bit segments.
//                  When a segment is fully written it is output from the assembler and its contents 
//                  are zeroed. The state machine maintains pointers to the written section of the
//                  accumulator and which segments can be read.
//                  A barrel shifter output of 65 bits or more can result in two segments being completed 
//                  in one clock cycle.
//
// 2/8/2022         Fix for EOS.
//----------------------------------------------------------------------------------------------------------------------
`ifndef HIT_ASSEM__SV
`define HIT_ASSEM__SV

`timescale 1ns / 1ps

module hit_assembler
(
    input   logic           clk             ,
    input   logic           reset           ,
    input   logic           restart         ,

    input   logic   [ 7:0]  tag_init        ,   // Tag to start output stream. Subsequent tags (internal) will be 11-bit
    input   logic   [ 1:0]  chip_id         ,   // 
    input   logic           en_chip_id      ,   // Enable chip ID[1:0]
    input   logic           en_eos          ,   // Enable min 6 zeros output to mark end of stream

    input   logic  [109:0]  din             ,   // Hit data in MSBs (addr,hitmap,ToTs)
    input   logic   [ 6:0]  din_size        ,   // Number of valid bits in din
    input   logic           din_eos         ,   // Input data end-of-stream. Used to generate new stream flag
    input   logic           din_eoe         ,   // Input data end-of-event. Used to increment tag, insert internal tags
    input   logic           din_dv          ,   // Input data valid
    output  logic           ready_out       ,   // Normally high. Goes low when either internal FIFO is over-threshold
    
    input   logic           ready_in        ,   // Normally high from downstream sink. Goes low when sink cannot accept data
    output  logic   [62:0]  dout            ,   // Output data. 
    output  logic           dout_ns         ,   // 'New stream' flag.  Bit-63 of output word 
    output  logic           dout_eos        ,   // Output EOS
    output  logic           dout_eoe        ,   // Output EOE
    output  logic           dout_dv             // Output data valid
);


    // Assembler FIFO connections
    // FIFO level to set 'ready' low. FIFO was 512.
    // Changed to 16 to build from distributed RAM instead of block RAM to save RAM inst 
    // Level set to 8 because of pipeline delays between event generator and this FIFO. 
    localparam C_FA_DLEVEL    = 6;   

    logic  [127:0]  fassem_din;
    logic           fassem_wr_en;
    logic           fassem_rd_en;
    logic  [127:0]  fassem_dout;
    logic           fassem_full;
    logic           fassem_overflow;
    logic           fassem_empty;
    logic           fassem_underflow;
    logic    [9:0]  fassem_dlevel;          // RAM in FIFO was originally 512. Reduced to 16 
    logic           fassem_not_empty;       // Inverted 'empty' for readability

    // Assembler FIFO output fields
    logic  [109:0]  fa_dout;        // {addr, hitmap, Tots}
    logic   [ 7:0]  fa_dout_size;   // Number of bits in hit fields
    logic           fa_dout_eos;    // Input data end-of-stream. Used to flush hits
    logic           fa_dout_eoe;    // Input data end-of-event.

    // Barrel shifter I/O
    logic  [109:0]  bs_din;         // {addr, hitmap, Tots}
    logic   [ 8:0]  bs_din_shift;   // Number of bits to shift
    logic           bs_din_eos;     // Input data end-of-stream. Used to flush hits
    logic           bs_din_eoe;     // Input data end-of-event.
    logic   [ 8:0]  bs_din_ptr;     // Input next bit pointer
    logic           bs_din_dv;      // Input data valid to barrel shifter
    logic  [314:0]  bs_dout;        // Output data. 5x 63-bit segments. (64th bit will be new-stream 1 or 0)
    logic           bs_dout_eos;    // Output end-of-sequence 
    logic           bs_dout_eos_d1; // Output end-of-sequence, delayed 1 cycle 
    logic           bs_dout_eos_d2; // Output end-of-sequence, delayed 2 cycle 
    logic           bs_dout_eoe;    // Output end-of-event
    logic   [ 8:0]  bs_dout_ptr;    // Output next bit pointer
    logic   [ 8:0]  bs_dout_ptr_d1; // Output next bit pointer, delayed 1 cycle
    logic           bs_dout_dv;     // Output data valid
    logic           bs_dout_dv_d1;  // Output data valid, delayed 1 cycle
    
    localparam C_SIZE_ACCUM   = 315;    // 4 x 63-bit register for barrel shifter output 

    logic   [62:0]  reg_accum0, reg_accum1, reg_accum2, reg_accum3, reg_accum4;
    logic           reg_accum0_wr , reg_accum1_wr , reg_accum2_wr , reg_accum3_wr , reg_accum4_wr ;     // Write flags, for debug
    logic           reg_accum0_eoe, reg_accum1_eoe, reg_accum2_eoe, reg_accum3_eoe, reg_accum4_eoe;     // End-of-Event flags

    // Four FIFOs for barrelshifter output (2 spare bits)
    localparam C_FBUF_DLEVEL    = 400;   // FIFO level to set 'ready' low  
    logic   [65:0]  fbuf0_din,   fbuf1_din,   fbuf2_din  , fbuf3_din   , fbuf4_din     ;
    logic           fbuf0_wr_en, fbuf1_wr_en, fbuf2_wr_en, fbuf3_wr_en , fbuf4_wr_en   ; 
    logic           fbuf0_rd_en, fbuf1_rd_en, fbuf2_rd_en, fbuf3_rd_en , fbuf4_rd_en   ; 
    logic   [65:0]  fbuf0_dout,  fbuf1_dout,  fbuf2_dout , fbuf3_dout  , fbuf4_dout    ;   
    logic           fbuf0_full,  fbuf1_full,  fbuf2_full , fbuf3_full  , fbuf4_full    ;  
    logic           fbuf0_oflow, fbuf1_oflow, fbuf2_oflow, fbuf3_oflow , fbuf4_oflow   ; 
    logic           fbuf0_empty, fbuf1_empty, fbuf2_empty, fbuf3_empty , fbuf4_empty   ; 
    logic           fbuf0_uflow, fbuf1_uflow, fbuf2_uflow, fbuf3_uflow , fbuf4_uflow   ; 
    logic   [ 9:0]  fbuf0_dlevel,fbuf1_dlevel,fbuf2_dlevel,fbuf3_dlevel,fbuf4_dlevel  ; 
    logic           fbuf0_empty_d1, fbuf1_empty_d1, fbuf2_empty_d1, fbuf3_empty_d1, fbuf4_empty_d1; 

    // Final output FIFO
    localparam C_FO_DLEVEL    = 400;   // FIFO level to set 'ready' low  
    logic   [65:0]  fo_din;
    logic           fo_wr_en; 
    logic           fo_rd_en; 
    logic   [65:0]  fo_dout;   
    logic           fo_full;  
    logic           fo_oflow; 
    logic           fo_empty; 
    logic           fo_uflow; 
    logic   [ 9:0]  fo_dlevel; 
    logic   [62:0]  fo_data;   
    logic           fo_eoe;   
    logic           fo_eos;   

    logic   [ 2:0]  next_wr_fbuf;       // 0,1,2,3,4
    integer         curr_rd_fbuf;
    logic   [ 4:0]  fbufs_rd_en;        // Bus of FIFO rd_en signals
    logic   [ 4:0]  fbufs_wr_en;        // Bus of FIFO wr_en signals
    logic   [ 4:0]  clr_accum;          // Bus of signals to clear accumulator segments
    logic   [ 8:0]  next_shift;         // Number of bits

    logic           hold_restart;

    // State machine for barrel shifter control 
    // Variables and state machine outputs
    enum {  S_BS_IDLE          ,   // Waiting for data to start
            S_BS_NEW           ,   // Start of stream. Set NS, Tag, chip_id
            S_BS_LOOP          ,   // Stream continuation
            S_BS_WAIT          ,   // Stream continuation
            S_BS_EOE           ,   // Write internal tag at end of event       
            S_BS_GAP               // Gap between EOS and starting a NEW stream
         }  sm_bs_state;

    logic   [ 7:0]  sm_tag;
    logic   [ 2:0]  sm_cnt_gap;
    

    // State machine for output data.
    enum {  S_OD_IDLE          ,   // Waiting for new stream data to start
            S_OD_LOOP          ,   // Stream continuation
            S_OD_EOS_EXTRA         // Write extra all-zero orphan bit word if necessary        
         }  sm_od_state;

  

    //--------------------------------------------------------------------------------------
    // FIFO for input data (16 words x 128-bit)
    //--------------------------------------------------------------------------------------
    fifo_assem  u_fifo_assem 
    (
        .clk        ( clk                   ),  // input                
        .srst       ( reset                 ),  // input              
        .din        ( fassem_din            ),  // input  [127:0]               
        .wr_en      ( fassem_wr_en          ),  // input            
        .rd_en      ( fassem_rd_en          ),  // input            
        .dout       ( fassem_dout           ),  // output [127:0]             
        .full       ( fassem_full           ),  // output        
        .overflow   ( fassem_overflow       ),  // output    
        .empty      ( fassem_empty          ),  // output       
        .underflow  ( fassem_underflow      ),  // output   
        .data_count ( fassem_dlevel         )   // output [  9:0] 
    );

    // Pack all inputs in FIFO
    //         128 bits     =      3  +   1    +   3   +   1    +  1  +   7     +   2  + 110
    assign fassem_din       = {3'b000, din_eoe, 3'b000, din_eos, 1'b0, din_size, 2'b00, din};
    assign fassem_wr_en     = din_dv;
    assign fassem_not_empty = ~fassem_empty;

    // Extract fields from FIFO output
    assign fa_dout          = fassem_dout[109:0];
    assign fa_dout_size     = fassem_dout[118:112];
    assign fa_dout_eos      = fassem_dout[120];
    assign fa_dout_eoe      = fassem_dout[124];

    assign bs_din_ptr       = next_shift;       // Pointer to next free bit after current din is shifted


    //----------------------------------------------------------------------------
    // State machine to calculate barrel shifter parameters and generate 
    // chip_id and tag words at the beginning of a stream.
    // End streams with correct number of zero bits.
    // Insert 11-bit internal tags {111, sm_tag} for new events in a continuing stream.
    //----------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin : pr_sm_bs 

        if (reset == 1'b1) begin

            sm_tag          <= 8'b00000000;
            bs_din          <= 0;
            bs_din_shift    <= 0;
            bs_din_eos      <= 1'b0; 
            bs_din_eoe      <= 1'b0; 
            bs_din_dv       <= 1'b0;
            next_shift      <= 0;
            fassem_rd_en    <= 1'b0;
            sm_bs_state     <= S_BS_IDLE;
            sm_cnt_gap      <= 3'b000;
        
        end else begin
    
            case (sm_bs_state)

                //--------------------------------------------
                // Wait for input data to begin
                // Cleared shifts in preparation for data.
                //--------------------------------------------
                S_BS_IDLE : begin

                    if (fassem_not_empty == 1'b1) begin
                        sm_bs_state     <= S_BS_NEW;
                    end

                    bs_din          <= 0;
                    bs_din_shift    <= 0;
                    bs_din_eos      <= 1'b0;
                    bs_din_eoe      <= 1'b0;
                    bs_din_dv       <= 1'b0;
                    sm_tag          <= tag_init;    // Initialize tag

                    next_shift      <= 0;
                    fassem_rd_en    <= 1'b0;        // Do not read FIFO
                    sm_cnt_gap      <= 3'b000;
                end

                //--------------------------------------------
                // Wait for input data to begin
                // First word of a new stream
                //--------------------------------------------
                S_BS_NEW : begin

                    if (fassem_not_empty == 1'b1) begin

                        bs_din_shift        <= next_shift;
                        bs_din_dv           <= 1'b1;

                        // Optional chip ID and non-optional event tag
                        if (en_chip_id == 1'b1)  begin
                            bs_din[109:108]     <= chip_id;     // 2-bit
                            bs_din[107:100]     <= sm_tag;      // 8-bit
                            next_shift          <= 10;
                        end
                        else begin                              // No chip_id
                            bs_din[109:102]     <= sm_tag;
                            next_shift          <= 8;
                        end

                        sm_bs_state     <= S_BS_WAIT;

                    end else begin
                        bs_din_dv       <= 1'b0;
                    end

                    fassem_rd_en        <= 1'b0;    // Do not read FIFO
                    bs_din_eos          <= 1'b0;
                    bs_din_eoe          <= 1'b0;
                end


                //--------------------------------------------------------
                // Continuation loop. 
                // Check for EOS and EOE to maintain tag value.
                // Insert zeros for EOS and internal tags.
                //--------------------------------------------------------
                S_BS_LOOP : begin

                    if ((fassem_dlevel == 1) & (fassem_rd_en == 1'b1) & (fassem_wr_en == 1'b0)) begin   // FIFO is going empty
                        bs_din_shift    <= 0;
                        bs_din_eos      <= 1'b0;
                        bs_din_eoe      <= 1'b0;
                        bs_din_dv       <= 1'b0;
                        fassem_rd_en    <= 1'b0;
                        sm_bs_state     <= S_BS_WAIT;

                    end else if (fassem_dlevel > 0) begin

                        fassem_rd_en    <= 1'b1;        // Read FIFO
                        bs_din          <= fa_dout; 
                        bs_din_dv       <= 1'b1;
                        bs_din_shift    <= next_shift;

                        if ((next_shift + fa_dout_size) > C_SIZE_ACCUM-1) begin
                            next_shift  <= next_shift + fa_dout_size - C_SIZE_ACCUM;
                        end else begin
                            next_shift  <= next_shift + fa_dout_size;        
                        end

                        if (fa_dout_eos == 1'b1)  begin                     // End of stream

                            sm_bs_state     <= S_BS_GAP;
                            bs_din_eos      <= 1'b1;

                            if (fa_dout_eoe == 1'b1) begin                  // End of event co-incides with end of stream
                                sm_tag      <= sm_tag + 1;                  // Increment tag for next event to be used at start of next stream
                                bs_din_eoe  <= 1'b1;
                            end

                        end else if (din_eoe == 1'b1) begin
                            sm_bs_state     <= S_BS_EOE;                    // Go to state to insert 11-bit internal tag in the current stream
                        end else begin
                            sm_bs_state     <= S_BS_WAIT;
                        end

                    end else begin
                        bs_din_eos          <= 1'b0;
                        bs_din_eoe          <= 1'b0;
                        bs_din_dv           <= 1'b0;
                        fassem_rd_en        <= 1'b0;
                    end
                end

                //--------------------------------------------------------
                // Insert a delay for chip_id and tag to be written 
                //--------------------------------------------------------
                S_BS_WAIT : begin
                    sm_bs_state         <= S_BS_LOOP;                  // Continue stream
                    bs_din_shift        <= 0;
                    bs_din_eos          <= 1'b0;
                    bs_din_eoe          <= 1'b0;
                    bs_din_dv           <= 1'b0;
                    fassem_rd_en        <= 1'b0;
                end

                //--------------------------------------------------------
                // End of event. Insert 11-bit tag into FIFO input as if it
                // was an input hit of length 11. 
                //--------------------------------------------------------
                S_BS_EOE : begin

                    bs_din[109:99]  <= {3'b111, sm_tag};        // 11-bit internal tag
                    bs_din_shift    <= next_shift;        
                    bs_din_eos      <= 1'b0;
                    bs_din_eoe      <= 1'b1;
                    bs_din_dv       <= 1'b1;

                    sm_tag          <= sm_tag + 1;              // Increment tag for next event
                    fassem_rd_en    <= 1'b0;                    // Do not read FIFO
                    next_shift      <= next_shift + 11;        
                    sm_bs_state     <= S_BS_LOOP;                  // Continue stream

                end


                //--------------------------------------------------------
                // Insert a delay gap before returning to IDLE 
                //--------------------------------------------------------
                S_BS_GAP : begin

                    if (sm_cnt_gap == 3'b111) begin
                        sm_bs_state    <= S_BS_IDLE;
                        sm_cnt_gap  <= 3'b000;
                    end else begin
                        sm_cnt_gap  <= sm_cnt_gap + 1;
                    end

                    fassem_rd_en    <= 1'b0;                    // Do not read FIFO
                    bs_din          <= 0;
                    bs_din_shift    <= 0;
                    bs_din_eos      <= 1'b0;
                    bs_din_eoe      <= 1'b0;
                    bs_din_dv       <= 1'b0;

                end

                //--------------------------------------------------------
                default : begin
                    sm_bs_state            <= S_BS_IDLE;
                end

            endcase
        end
    end


    //-----------------------------------------------------------
    // Barrel shifter for 110-bit input data into 192-bit output 
    //-----------------------------------------------------------
    hit_barrelshift u_hit_barrelshift
    (
        .clk        ( clk           ),  // input            
        .reset      ( reset         ),  // input            

        .din        ( bs_din        ),  // input   [109:0]     {addr, hitmap, Tots}
        .din_shift  ( bs_din_shift  ),  // input    [ 8:0]     Shift input data right, with rotation, by this amount. 0-314
        .din_eos    ( bs_din_eos    ),  // input               Input data end-of-stream.
        .din_eoe    ( bs_din_eoe    ),  // input               Input data end-of-event
        .din_ptr    ( bs_din_ptr    ),  // input    [ 8:0]     
        .din_dv     ( bs_din_dv     ),  // input               Input data valid

        .dout       ( bs_dout       ),  // output  [314:0]     Shifted din
        .dout_eos   ( bs_dout_eos   ),  // output              Pipelined din_eos
        .dout_eoe   ( bs_dout_eoe   ),  // output              Pipelined din_eoe
        .dout_ptr   ( bs_dout_ptr   ),  // output   [ 8:0]     Pipelined din_ptr
        .dout_dv    ( bs_dout_dv    )   // output
    );


    //--------------------------------------------------------------------------------------
    // Block to maintain the accumulator registers with the barrel shifter output data
    // and clear the written segments.
    //     reg_accum0       <= bs_dout[314:252];
    //     reg_accum1       <= bs_dout[251:189];
    //     reg_accum2       <= bs_dout[188:126];
    //     reg_accum3       <= bs_dout[125: 63];
    //     reg_accum4       <= bs_dout[ 62:  0];
    // *** NOTE **** : Barrel shifter output is OR'ed into the accum regs. This means that
    // ***             all barrel shifter outputs that are not shifted data must be zero and
    // ***             accum regs must be cleared after being written.
    //--------------------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin : pr_accum_wr                            

        bs_dout_dv_d1   <= bs_dout_dv;
        bs_dout_ptr_d1  <= bs_dout_ptr;
        bs_dout_eos_d1  <= bs_dout_eos;
        bs_dout_eos_d2  <= bs_dout_eos_d1;

        if (reset == 1'b1) begin

            reg_accum0      <= 63'b0;
            reg_accum1      <= 63'b0;
            reg_accum2      <= 63'b0;
            reg_accum3      <= 63'b0;
            reg_accum4      <= 63'b0;

            reg_accum0_eoe  <= 1'b0;  reg_accum0_wr <= 1'b0;
            reg_accum1_eoe  <= 1'b0;  reg_accum1_wr <= 1'b0;
            reg_accum2_eoe  <= 1'b0;  reg_accum2_wr <= 1'b0;
            reg_accum3_eoe  <= 1'b0;  reg_accum3_wr <= 1'b0;
            reg_accum4_eoe  <= 1'b0;  reg_accum4_wr <= 1'b0;

        // If there is new barrel shifter output, OR it with the accumulator unless a 'clear' signal is active.
        // Set each accumulator EOS if necessary.
        end else if (bs_dout_dv == 1'b1) begin

            //----------------------------------------------------------------------------
            if (clr_accum[0] == 1'b1) begin
                reg_accum0      <= 0;
                reg_accum0_wr   <= 1'b0;
            end else begin
                reg_accum0      <= reg_accum0 | bs_dout[314:252];
                reg_accum0_wr   <= 1'b1;
            end

            //----------------------------------------------------------------------------
            if (clr_accum[1] == 1'b1) begin
                reg_accum1      <= 0;
                reg_accum1_wr   <= 1'b0;
            end else begin
                reg_accum1      <= reg_accum1 | bs_dout[251:189];
                reg_accum1_wr   <= 1'b1;
            end

            //----------------------------------------------------------------------------
            if (clr_accum[2] == 1'b1) begin
                reg_accum2      <= 0;
                reg_accum2_wr   <= 1'b0;
            end else begin
                reg_accum2      <= reg_accum2 | bs_dout[188:126];
                reg_accum2_wr   <= 1'b1;
            end

            //----------------------------------------------------------------------------
            if (clr_accum[3] == 1'b1) begin
                reg_accum3      <= 0;
                reg_accum3_wr   <= 1'b0;
            end else begin
                reg_accum3      <= reg_accum3 | bs_dout[125:63];
                reg_accum3_wr   <= 1'b1;
            end

            //----------------------------------------------------------------------------
            if (clr_accum[4] == 1'b1) begin
                reg_accum4      <= 0;
                reg_accum4_wr   <= 1'b0;
            end else begin
                reg_accum4      <= reg_accum4 | bs_dout[62:0];
                reg_accum4_wr   <= 1'b1;
            end
        end


        // Just respond to 'clear' signals when bs_dout_dv is low
        else if (bs_dout_dv == 1'b0) begin
            reg_accum0_wr   <= 1'b0;
            reg_accum1_wr   <= 1'b0;
            reg_accum2_wr   <= 1'b0;
            reg_accum3_wr   <= 1'b0;
            reg_accum4_wr   <= 1'b0;

            if (clr_accum[0] == 1'b1) begin
                reg_accum0      <= 0;
            end

            if (clr_accum[1] == 1'b1) begin
                reg_accum1      <= 0;
            end

            if (clr_accum[2] == 1'b1) begin
                reg_accum2      <= 0;
            end

            if (clr_accum[3] == 1'b1) begin
                reg_accum3      <= 0;
            end

            if (clr_accum[4] == 1'b1) begin
                reg_accum4      <= 0;
            end
        end

    end 


    //--------------------------------------------------------------------------------------
    // Compare pointers and write barrel shifter accum regs to the four buffer FIFOs whenever
    // they contain valid data. One or two FIFOs can normally be written in any clock cycle.
    // However, on an end-of-stream, the last word can be incomplete but it is still written.
    // Maintain pointer to the next FIFO to be written.
    // Generate the 'clear' signals to the accum regs once they have been written.
    //--------------------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin : pr_wr_fbufs

        if ((reset == 1'b1) || (bs_dout_eos_d2 == 1'b1)) begin

            fbuf0_din       <= 0;
            fbuf1_din       <= 0;
            fbuf2_din       <= 0;
            fbuf3_din       <= 0;
            fbuf4_din       <= 0;

            fbufs_wr_en     <= 5'b00000;
            clr_accum       <= 5'b11111;

            next_wr_fbuf    <= 3'b000;

        end else if (bs_dout_dv_d1 == 1'b1) begin

            //------------------------------------
            // Currently pointing to FIFO 0
            //------------------------------------
            if (next_wr_fbuf == 3'b000) begin

                // EOS and pointer is in third word, write complete accum0,1 and incomplete accum2 to FIFOs
                if          ((bs_dout_ptr_d1 > 125) && (bs_dout_eos_d1 == 1'b1)) begin 

                    fbuf0_din       <= {          1'b0, reg_accum0_eoe, 1'b0, reg_accum0};
                    fbuf1_din       <= {          1'b0, reg_accum1_eoe, 1'b0, reg_accum1};
                    fbuf2_din       <= {bs_dout_eos_d1, reg_accum2_eoe, 1'b0, reg_accum2};

                    fbufs_wr_en     <= 5'b00111;
                    clr_accum       <= 5'b00111;
                    next_wr_fbuf    <= 3'b011;

                // Pointer is past second word, write accum0 and 1 to FIFO
                // or EOS and pointer is in second word, write accum0 and incomplete accum1 to FIFOs
                end else if ((bs_dout_ptr_d1 > 125) || ((bs_dout_eos_d1 == 1'b1) && (bs_dout_ptr_d1 > 62))) begin

                    fbuf0_din       <= {          1'b0, reg_accum0_eoe, 1'b0, reg_accum0};
                    fbuf1_din       <= {bs_dout_eos_d1, reg_accum1_eoe, 1'b0, reg_accum1};

                    fbufs_wr_en     <= 5'b00011;
                    clr_accum       <= 5'b00011;
                    next_wr_fbuf    <= 3'b010;

                // Pointer is past first word, write complete accum0 to FIFO
                // or EOS and pointer is in first word, write incomplete accum0 to FIFO
                end else if ((bs_dout_ptr_d1 > 62) || ((bs_dout_eos_d1 == 1'b1) && (bs_dout_ptr_d1 > 0))) begin

                    fbuf0_din       <= {bs_dout_eos_d1, reg_accum0_eoe, 1'b0, reg_accum0};

                    fbufs_wr_en     <= 5'b00001;
                    clr_accum       <= 5'b00001;
                    next_wr_fbuf    <= 3'b001;

                end

            end

            //------------------------------------
            // Currently pointing to FIFO 1
            //------------------------------------
            if (next_wr_fbuf == 3'b001) begin

                // EOS and pointer is in fourth word, write complete accum1,2 and incomplete accum3 to FIFOs
                if ((bs_dout_ptr_d1 > 188) && (bs_dout_eos_d1 == 1'b1)) begin
                
                    fbuf1_din       <= {          1'b0, reg_accum1_eoe, 1'b0, reg_accum1};
                    fbuf2_din       <= {          1'b0, reg_accum2_eoe, 1'b0, reg_accum2};
                    fbuf3_din       <= {bs_dout_eos_d1, reg_accum3_eoe, 1'b0, reg_accum3};
                
                    fbufs_wr_en     <= 5'b01110;
                    clr_accum       <= 5'b01110;
                    next_wr_fbuf    <= 3'b100;
                
                // Pointer is past third word, write  complete accum1, accum2 to FIFOs
                // or EOS and pointer is in third word, write complete accum1 and incomplete accum2 to FIFOs
                end else if ((bs_dout_ptr_d1 > 188) || ((bs_dout_eos_d1 == 1'b1) && (bs_dout_ptr_d1 > 125))) begin
                
                    fbuf1_din       <= {          1'b0, reg_accum1_eoe, 1'b0, reg_accum1};
                    fbuf2_din       <= {bs_dout_eos_d1, reg_accum2_eoe, 1'b0, reg_accum2};
                
                    fbufs_wr_en     <= 5'b00110;
                    clr_accum       <= 5'b00110;
                    next_wr_fbuf    <= 3'b011;
                
                // Pointer is past second word, write complete accum1 to FIFO
                // or EOS and pointer is in second word, write incomplete accum1 to FIFO
                end else if ((bs_dout_ptr_d1 > 125) || ((bs_dout_eos_d1 == 1'b1) && (bs_dout_ptr_d1 > 62))) begin
                
                    fbuf1_din       <= {bs_dout_eos_d1, reg_accum1_eoe, 1'b0, reg_accum1};
                
                    fbufs_wr_en     <= 5'b00010;
                    clr_accum       <= 5'b00010;
                    next_wr_fbuf    <= 3'b010;
                
                end

            end

            //------------------------------------
            // Currently pointing to FIFO 2
            //------------------------------------
            if (next_wr_fbuf == 3'b010) begin

                // EOS and pointer is in fifth word, write complete accum3,4 and incomplete accum5 to FIFOs
                if ((bs_dout_ptr_d1 > 251) && (bs_dout_eos_d1 == 1'b1)) begin

                    fbuf2_din       <= {          1'b0, reg_accum2_eoe, 1'b0, reg_accum2};
                    fbuf3_din       <= {          1'b0, reg_accum3_eoe, 1'b0, reg_accum3};
                    fbuf4_din       <= {bs_dout_eos_d1, reg_accum4_eoe, 1'b0, reg_accum4};

                    fbufs_wr_en     <= 5'b11100;
                    clr_accum       <= 5'b11100;
                    next_wr_fbuf    <= 3'b000;

                // Pointer is past fourth word, write complete accum2, accum3 to FIFOs
                // or EOS and pointer is in fourth word, write complete accum2 and incomplete accum3 to FIFOs
                end else if ((bs_dout_ptr_d1 > 251) || ((bs_dout_eos_d1 == 1'b1) && (bs_dout_ptr_d1 > 188))) begin

                    fbuf2_din       <= {          1'b0, reg_accum2_eoe, 1'b0, reg_accum2};
                    fbuf3_din       <= {bs_dout_eos_d1, reg_accum3_eoe, 1'b0, reg_accum3};

                    fbufs_wr_en     <= 5'b01100;
                    clr_accum       <= 5'b01100;
                    next_wr_fbuf    <= 3'b100;

                // Pointer is past third word. Write complete accum2 to FIFO
                // or EOS and pointer is in third word, write incomplete accum2 to FIFO
                end else if ((bs_dout_ptr_d1 > 188) || ((bs_dout_eos_d1 == 1'b1) && (bs_dout_ptr_d1 > 125))) begin

                    fbuf2_din       <= {bs_dout_eos_d1, reg_accum2_eoe, 1'b0, reg_accum2};

                    fbufs_wr_en     <= 5'b00100;
                    clr_accum       <= 5'b00100;
                    next_wr_fbuf    <= 3'b011;

                end

            end

            //------------------------------------
            // Currently pointing to FIFO 3
            //------------------------------------
            if (next_wr_fbuf == 3'b011) begin

                // EOS and pointer is wrapped and in first word, write complete accum3, accum4 and incomplete accum0 to FIFOs
                if ((bs_dout_ptr_d1 < 63) && (bs_dout_eos_d1 == 1'b1)) begin

                    fbuf3_din       <= {          1'b0, reg_accum3_eoe, 1'b0, reg_accum3};
                    fbuf4_din       <= {          1'b0, reg_accum4_eoe, 1'b0, reg_accum4};
                    fbuf0_din       <= {bs_dout_eos_d1, reg_accum0_eoe, 1'b0, reg_accum0};

                    fbufs_wr_en     <= 5'b11001;
                    clr_accum       <= 5'b11001;
                    next_wr_fbuf    <= 3'b001;

                // Pointer is wrapped, past fifth word, write complete accum3, accum4 to FIFOs
                // or EOS and pointer is in fifth word, write complete accum3 and incomplete accum4 to FIFOs
                end else if ((bs_dout_ptr_d1 < 63) || ((bs_dout_eos_d1 == 1'b1) && (bs_dout_ptr_d1 > 251))) begin

                    fbuf3_din       <= {          1'b0, reg_accum3_eoe, 1'b0, reg_accum3};
                    fbuf4_din       <= {bs_dout_eos_d1, reg_accum4_eoe, 1'b0, reg_accum4};

                    fbufs_wr_en     <= 5'b11000;
                    clr_accum       <= 5'b11000;
                    next_wr_fbuf    <= 3'b000;

                // Pointer is past fourth word. Write complete accum3 to FIFO
                // or EOS and pointer is in fourth word, write incomplete accum3 to FIFO
                end else if ((bs_dout_ptr_d1 > 251) || ((bs_dout_eos_d1 == 1'b1) && (bs_dout_ptr_d1 > 188))) begin

                    fbuf3_din       <= {bs_dout_eos_d1, reg_accum3_eoe, 1'b0, reg_accum3};

                    fbufs_wr_en     <= 5'b01000;
                    clr_accum       <= 5'b01000;
                    next_wr_fbuf    <= 3'b100;

                end

            end

            //------------------------------------
            // Currently pointing to FIFO 4
            //------------------------------------
            if (next_wr_fbuf == 3'b100) begin

                // Pointer is wrapped (past fifth word). Write complete accum4 to FIFO
                // or EOS and pointer is in fifth word, write incomplete accum4 to FIFO
                if (((bs_dout_ptr_d1 < 63) && (bs_dout_eos_d1 == 1'b0)) || ((bs_dout_eos_d1 == 1'b1) && (bs_dout_ptr_d1 > 251))) begin

                    fbuf4_din       <= {bs_dout_eos_d1, reg_accum4_eoe, 1'b0, reg_accum4};

                    fbufs_wr_en     <= 5'b10000;
                    clr_accum       <= 5'b10000;
                    next_wr_fbuf    <= 3'b000;

                // Pointer is wrapped, and past first word, write complete accum4, accum0 to FIFOs
                // or EOS and pointer is in first word, write accum4 and accum0 to FIFOs
                end else if (((bs_dout_ptr_d1 < 126) && (bs_dout_eos_d1 == 1'b0)) || ((bs_dout_eos_d1 == 1'b1) && (bs_dout_ptr_d1 < 63))) begin

                    fbuf4_din       <= {          1'b0, reg_accum4_eoe, 1'b0, reg_accum4};
                    fbuf0_din       <= {bs_dout_eos_d1, reg_accum0_eoe, 1'b0, reg_accum0};

                    fbufs_wr_en     <= 5'b10001;
                    clr_accum       <= 5'b10001;
                    next_wr_fbuf    <= 3'b001;

                // EOS and pointer is wrapped (and past first word). Write complete accum4, accum0 and incomplete accum1 to FIFO
                end else if ((bs_dout_ptr_d1 < 126) && (bs_dout_eos_d1 == 1'b1)) begin

                    fbuf4_din       <= {          1'b0, reg_accum4_eoe, 1'b0, reg_accum4};
                    fbuf0_din       <= {          1'b0, reg_accum0_eoe, 1'b0, reg_accum0};
                    fbuf1_din       <= {bs_dout_eos_d1, reg_accum1_eoe, 1'b0, reg_accum1};

                    fbufs_wr_en     <= 5'b10011;
                    clr_accum       <= 5'b10011;
                    next_wr_fbuf    <= 3'b010;

                end

            end

        end else begin
   
            fbufs_wr_en     <= 5'b00000;
            clr_accum       <= 5'b00000;
            fbuf0_din       <= 0;      // Remove these once debugged
            fbuf1_din       <= 0;
            fbuf2_din       <= 0;
            fbuf3_din       <= 0;
            fbuf4_din       <= 0;
        end

    end

    assign fbuf0_wr_en  = fbufs_wr_en[0];
    assign fbuf1_wr_en  = fbufs_wr_en[1];
    assign fbuf2_wr_en  = fbufs_wr_en[2];
    assign fbuf3_wr_en  = fbufs_wr_en[3];
    assign fbuf4_wr_en  = fbufs_wr_en[4];


    //--------------------------------------------------------------------------------------
    // Five FIFOs for 64-bit data. Each FIFO buffers one of the 63-bit segments of the barrel
    // shifter output and the NS bit. The shifter output can be 110 bits (>63 bits) which 
    // can sometimes produce two 63-bit output segments instead of one. 
    // Equivalent to a single FIFO except that only 1 or 2 segments are written at a time.
    // e.g. 0,  1 and 2, 3, 4, 0, 1, 2, 3 and 4, 0 and 1, 2, 3, 4 and 0, 1, etc.
    // Output reads occur from each FIFO in turn e.g. 0,1,2,3,4,0,1,2,3,4, ...
    //--------------------------------------------------------------------------------------
    fifo_512x66b    u_fbuf0 
    (
        .clk        ( clk           ),      // input  
        .srst       ( reset         ),      // input  

        .din        ( fbuf0_din     ),      // input  [65:0] 
        .wr_en      ( fbuf0_wr_en   ),      // input  

        .rd_en      ( fbuf0_rd_en   ),      // input  
        .dout       ( fbuf0_dout    ),      // output [65:0]  eos, eoe, sos, data[62:0]

        .full       ( fbuf0_full    ),      // output 
        .overflow   ( fbuf0_oflow   ),      // output 
        .empty      ( fbuf0_empty   ),      // output 
        .underflow  ( fbuf0_uflow   ),      // output 
        .data_count ( fbuf0_dlevel  )       // output [9:0] 
    );

    //--------------------------------------------------------------------------------------
    fifo_512x66b    u_fbuf1 
    (
        .clk        ( clk           ),      // input  
        .srst       ( reset         ),      // input  

        .din        ( fbuf1_din     ),      // input  [65:0] 
        .wr_en      ( fbuf1_wr_en   ),      // input  

        .rd_en      ( fbuf1_rd_en   ),      // input  
        .dout       ( fbuf1_dout    ),      // output [65:0] 

        .full       ( fbuf1_full    ),      // output 
        .overflow   ( fbuf1_oflow   ),      // output 
        .empty      ( fbuf1_empty   ),      // output 
        .underflow  ( fbuf1_uflow   ),      // output 
        .data_count ( fbuf1_dlevel  )       // output [9:0] 
    );

    //--------------------------------------------------------------------------------------
    fifo_512x66b    u_fbuf2 
    (
        .clk        ( clk           ),      // input  
        .srst       ( reset         ),      // input  

        .din        ( fbuf2_din     ),      // input  [65:0] 
        .wr_en      ( fbuf2_wr_en   ),      // input  

        .rd_en      ( fbuf2_rd_en   ),      // input  
        .dout       ( fbuf2_dout    ),      // output [65:0] 

        .full       ( fbuf2_full    ),      // output 
        .overflow   ( fbuf2_oflow   ),      // output 
        .empty      ( fbuf2_empty   ),      // output 
        .underflow  ( fbuf2_uflow   ),      // output 
        .data_count ( fbuf2_dlevel  )       // output [9:0] 
    );

    //--------------------------------------------------------------------------------------
    fifo_512x66b    u_fbuf3 
    (
        .clk        ( clk           ),      // input  
        .srst       ( reset         ),      // input  

        .din        ( fbuf3_din     ),      // input  [65:0] 
        .wr_en      ( fbuf3_wr_en   ),      // input  

        .rd_en      ( fbuf3_rd_en   ),      // input  
        .dout       ( fbuf3_dout    ),      // output [65:0] 

        .full       ( fbuf3_full    ),      // output 
        .overflow   ( fbuf3_oflow   ),      // output 
        .empty      ( fbuf3_empty   ),      // output 
        .underflow  ( fbuf3_uflow   ),      // output 
        .data_count ( fbuf3_dlevel  )       // output [9:0] 
    );

    //--------------------------------------------------------------------------------------
    fifo_512x66b    u_fbuf4 
    (
        .clk        ( clk           ),      // input  
        .srst       ( reset         ),      // input  

        .din        ( fbuf4_din     ),      // input  [65:0] 
        .wr_en      ( fbuf4_wr_en   ),      // input  

        .rd_en      ( fbuf4_rd_en   ),      // input  
        .dout       ( fbuf4_dout    ),      // output [65:0] 

        .full       ( fbuf4_full    ),      // output 
        .overflow   ( fbuf4_oflow   ),      // output 
        .empty      ( fbuf4_empty   ),      // output 
        .underflow  ( fbuf4_uflow   ),      // output 
        .data_count ( fbuf4_dlevel  )       // output [9:0] 
    );


    //--------------------------------------------------------------------------------------
    // Block to read the buffer FIFOs in turn and write data to a final output FIFO.
    //--------------------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin : pr_rd_fbufs

        fbuf0_empty_d1 <= fbuf0_empty;
        fbuf1_empty_d1 <= fbuf1_empty;
        fbuf2_empty_d1 <= fbuf2_empty;
        fbuf3_empty_d1 <= fbuf3_empty;
        fbuf4_empty_d1 <= fbuf4_empty;

        if ((reset == 1'b1) || ((fo_eos == 1'b1) && (fo_empty == 1'b0))) begin

            fbufs_rd_en     <= 5'b00000;
            fo_wr_en        <= 1'b0;
            fo_din          <= 0;
            curr_rd_fbuf    <= 0;

        end else if ((curr_rd_fbuf == 0) && (fbuf0_empty_d1 == 1'b0)) begin

            fbufs_rd_en     <= 5'b00001;
            fo_wr_en        <= 1'b1;
            fo_din          <= fbuf0_dout;  
            curr_rd_fbuf    <= 1;

        end else if ((curr_rd_fbuf == 1) && (fbuf1_empty_d1 == 1'b0)) begin

            fbufs_rd_en     <= 5'b00010;
            fo_wr_en        <= 1'b1;
            fo_din          <= fbuf1_dout;
            curr_rd_fbuf    <= 2;

        end else if ((curr_rd_fbuf == 2) && (fbuf2_empty_d1 == 1'b0)) begin

            fbufs_rd_en     <= 5'b00100;
            fo_wr_en        <= 1'b1;
            fo_din          <= fbuf2_dout;
            curr_rd_fbuf    <= 3;

        end else if ((curr_rd_fbuf == 3) && (fbuf3_empty_d1 == 1'b0)) begin

            fbufs_rd_en     <= 5'b01000;
            fo_wr_en        <= 1'b1;
            fo_din          <= fbuf3_dout;
            curr_rd_fbuf    <= 4;

        end else if ((curr_rd_fbuf == 4) && (fbuf4_empty_d1 == 1'b0)) begin

            fbufs_rd_en     <= 5'b10000;
            fo_wr_en        <= 1'b1;
            fo_din          <= fbuf4_dout;
            curr_rd_fbuf    <= 0;

        end else begin

            fbufs_rd_en     <= 5'b00000;
            fo_wr_en        <= 1'b0;
            fo_din          <= 0;

        end
    end 

    assign fbuf0_rd_en  = fbufs_rd_en[0];
    assign fbuf1_rd_en  = fbufs_rd_en[1];
    assign fbuf2_rd_en  = fbufs_rd_en[2];
    assign fbuf3_rd_en  = fbufs_rd_en[3];
    assign fbuf4_rd_en  = fbufs_rd_en[4];



    //--------------------------------------------------------------------------------------
    // Final output FIFO
    //--------------------------------------------------------------------------------------
    fifo_512x66b    u_fout
    (
        .clk        ( clk           ),      // input  
        .srst       ( reset         ),      // input  

        .din        ( fo_din        ),      // input  [65:0] 
        .wr_en      ( fo_wr_en      ),      // input  

        .rd_en      ( fo_rd_en      ),      // input  
        .dout       ( fo_dout       ),      // output [65:0] 

        .full       ( fo_full       ),      // output 
        .overflow   ( fo_oflow      ),      // output 
        .empty      ( fo_empty      ),      // output 
        .underflow  ( fo_uflow      ),      // output 
        .data_count ( fo_dlevel     )       // output [9:0] 
    );

    assign  fo_rd_en    = ~fo_empty & ready_in;
    
    // Rename bits from final output FIFO
    assign  fo_data     = fo_dout[62:0];   
    assign  fo_eoe      = fo_dout[64];   
    assign  fo_eos      = fo_dout[65];   


    //--------------------------------------------------------------------------------------
    // Drive 'ready_out' low to slow down data generation when any buffer FIFO or the
    // output FIFO is over threshold.
    //--------------------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin
        if (reset == 1'b1)
            ready_out   <= 1'b1;

        else if (  (fbuf0_dlevel > C_FBUF_DLEVEL) || (fbuf1_dlevel > C_FBUF_DLEVEL) 
                || (fbuf2_dlevel > C_FBUF_DLEVEL) || (fbuf3_dlevel > C_FBUF_DLEVEL) 
                || (fbuf4_dlevel > C_FBUF_DLEVEL)  
                || (fassem_dlevel > C_FA_DLEVEL)
                || (fo_dlevel    > C_FO_DLEVEL)
                )
            ready_out   <= 1'b0;
        else
            ready_out   <= 1'b1;
    end 


    //--------------------------------------------------------------------------------------
    // Hold 'restart' until new stream begins.
    //--------------------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin
        if (reset == 1'b1)
            hold_restart    <= 1'b0;

        else if (restart == 1'b1)
            hold_restart    <= 1'b1;

        else if (sm_bs_state == S_BS_NEW)
            hold_restart    <= 1'b0;
    
     end
 

    //----------------------------------------------------------------------------
    // Data output state machine
    // State machine to generate 'new_stream' (dout_ns) and insert an additional
    // all-zero word if the last output word has less than 6 zeros.
    // This extra word insertion is optional and is enabled by the 'en_eos' input.
    //----------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin : pr_sm_od

        if (reset == 1'b1) begin

            dout_dv     <= 1'b0;
            dout_ns     <= 1'b0;
            dout        <= 63'b0;   // fo_dout[62:0];   // 
            dout_eoe    <= 1'b0;    // fo_dout[64];     // EOE (end-of-event)
            dout_eos    <= 1'b0;    // fo_dout[65];     // EOS (end_of_stream)

            sm_od_state <= S_OD_IDLE;
        
        end else begin
    
            case (sm_od_state)

                //--------------------------------------------
                // Wait for input data to begin stream
                //--------------------------------------------
                S_OD_IDLE : begin

                    if (~fo_empty & ready_in) begin

                        if (fo_eos == 1'b0) begin       // Typical
                            sm_od_state     <= S_OD_LOOP;
                            dout_eos        <= 1'b0;

                        // EOS set on first word of stream (not typical)
                        end else begin                                             

                            // Enough zeros in last word, or don't care when disabled
                            if ((fo_dout[5:0] == 6'b0) || (en_eos == 1'b0)) begin   
                                sm_od_state     <= S_OD_IDLE;
                                dout_eos        <= 1'b1;
                            end else begin                          // Go to insert extra, all-zero last word in stream
                                sm_od_state     <= S_OD_EOS_EXTRA;
                                dout_eos        <= 1'b0;
                            end

                        end

                        dout_dv     <= 1'b1;
                        dout_ns     <= 1'b1;            // Set 'new stream'
                        dout        <= fo_dout[62:0];   // 
                        dout_eoe    <= fo_eoe;          // EOE (end-of-event)

                    end else begin

                        dout_dv     <= 1'b0;
                        dout_ns     <= 1'b0;
                        dout        <= 63'b0;
                        dout_eoe    <= 1'b0;
                        dout_eos    <= 1'b0;
                    end

                end


                //--------------------------------------------------------
                // Continuation loop until EOS seen
                // Insert zeros for EOS and internal tags.
                //--------------------------------------------------------
                S_OD_LOOP : begin

                    if (~fo_empty & ready_in) begin

                        if (fo_eos == 1'b0) begin       // Typical
                            sm_od_state     <= S_OD_LOOP;
                            dout_eos        <= 1'b0;

                        // EOS set on first word of stream (not typical)
                        end else begin                                             

                            // Enough zeros in last word, or don't care when disabled
                            if ((fo_dout[5:0] == 6'b0) || (en_eos == 1'b0)) begin   
                                sm_od_state     <= S_OD_IDLE;
                                dout_eos        <= 1'b1;
                            end else begin                          // Go to insert extra, all-zero last word in stream
                                sm_od_state     <= S_OD_EOS_EXTRA;
                                dout_eos        <= 1'b0;            // Suppress EOS
                            end

                        end

                        dout_dv     <= 1'b1;
                        dout_ns     <= 1'b0;          
                        dout        <= fo_dout[62:0]; 
                        dout_eoe    <= fo_eoe;   

                    end else begin

                        dout_dv     <= 1'b0;
                        dout_ns     <= 1'b0;
                        dout        <= 63'b0;
                        dout_eoe    <= 1'b0;
                        dout_eos    <= 1'b0;
                    end
                end


                //--------------------------------------------------------
                // End-of-stream.  Output an extra 63-bit word that is all zero, 
                //--------------------------------------------------------
                S_OD_EOS_EXTRA : begin

                    sm_od_state     <= S_OD_IDLE;
                    dout_dv         <= 1'b1;
                    dout_ns         <= 1'b0;
                    dout            <= 63'b0;
                    dout_eoe        <= 1'b0;
                    dout_eos        <= 1'b1;

                end


                //--------------------------------------------------------
                default : begin
                    sm_od_state     <= S_OD_IDLE;
                    dout_dv         <= 1'b0;
                    dout_ns         <= 1'b0;
                    dout            <= 63'b0;
                    dout_eoe        <= 1'b0;
                    dout_eos        <= 1'b0;
                end

            endcase
        end
    end


endmodule
    
`endif

