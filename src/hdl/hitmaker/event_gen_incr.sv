//----------------------------------------------------------------------------
// FSM that increments the hitmap value from 0x0001 to 0xFFFF while incrementing
// the row by 1 (to set 'is_neigbor) or 2
//
// parameter X_MAX  = 400; 
// parameter Y_MAX  = 384; 
//----------------------------------------------------------------------------
`timescale 1ns / 1ps

`include "..\defines_rd53b.sv"

module event_gen
(
    input   logic           clk             ,  
    input   logic           reset           , 

    input   logic           enable          , // Enable stream generation. 
    input   logic           start           , // Begin stream generation if enabled
    input   logic           ready           , // Downstream block can accept new hit data. This should be tied high for a real system with no back-pressure.
    output  logic           busy            , // Set low after end of a stream if enable is low.   
    
    input   logic   [31:0]  seed            , // Seed to initialize the pseudo-random number generator

    // Controls for stream size. The first condition to be reached, terminates each stream
    input   logic   [15:0]  hits_per_stream , // Number of hits in a stream.
    input   logic           hitmaker_dout_dv, // Set high when hitmaker block outputs a new word
    input   logic   [15:0]  words_per_stream, // Number of 64-bit words output from the hitmaker in a stream. Approximate. Set to ~buffer size in decoder.

    output  logic           dout_dv         , //  Set when new dout_hit produced  
    output  logic           dout_eos        , //  Set for end-of-stream. Last hit in stream 
    output  logic           dout_eoe        , //  Set for end-of-event. Last hit in an event 
    output  logic   [ 7:0]  dout_hit_qrow   , // 
    output  logic   [ 5:0]  dout_hit_ccol   , // 
    output  logic   [15:0]  dout_hit_hitmap   // 
);
 
  parameter C_LAST_HITMAP   = 16'hFFFF; // For normal use 
  //parameter C_LAST_HITMAP = 16'h0080; // For debugging 

  // Use large gap in tb_decode_engine_xx sims because decoder requires input buffer FIFO to be empty at the end of a stream decode. 
  // This is handled by the distrib_stream in multi-decoder sims
  parameter C_STREAM_GAP    = 200; 
    
    logic   [31:0]  random_dout;
    logic           select_qrow_incr;

    logic           din_dv_cl;          // Data valid out from cluster_3x3
    logic           din_dv_lv;          // Data valid out from vertical line
    logic   [ 8:0]  din_x;              //     
    logic   [ 8:0]  din_y;              //     
    logic   [ 8:0]  din_bitset;         //     
    logic   [ 8:0]  din_length;         //     

    logic           sm_wr_ready;          //
    logic   [15:0]  sm_cnt_hitmap;
    logic   [15:0]  cnt_hits_in_stream;
    logic   [15:0]  cnt_words_in_stream;
    logic   [31:0]  cnt_stream_gap;       //  Counter for interval between EOS and start of next stream
    logic           sm_dout_dv;           //  Set when new dout_hit produced  
    logic           sm_dout_eos;          //  Set at end-of-stream 
    logic           sm_dout_eoe;          //  Set at end-of-event 
    logic   [15:0]  hold_hits_per_stream; //  Changes take effect at end-of-stream
    logic   [15:0]  hold_words_per_stream;//  Changes take effect at end-of-stream

    // A 'zero hit'
    t_hit           hit_zero;
    assign hit_zero.ccol    = 0;
    assign hit_zero.qrow    = 0;
    assign hit_zero.bitmap  = 0;

    assign select_qrow_incr = random_dout[0]; // Increment qrow randomly by 1 or 2
    //assign select_qrow_incr = 1'b1;           // Increment qrow by 2
    //assign select_qrow_incr = 1'b0;           // Increment qrow by 1

    //----------------------------------------------------------------------------
    // FSM A
    // Maintains X and Y pixel address.
    //----------------------------------------------------------------------------
    enum {
        S_WR_IDLE   ,        // Wait for 'start'
        S_WR_INCR   ,        // Write (trigger) an incrementing set of hitmap hits
        S_END_OF_STREAM      // Complete a stream
    } state_wr;


    //----------------------------------------------------------------------------
    // Count the number of words output by the hitmaker block (last stage : hit_assem)
    // Reset at end of output stream
    //----------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin
        if (reset) begin
            cnt_words_in_stream     <= 0;

        end else if ((sm_dout_dv == 1'b1) && (sm_dout_eos == 1'b1)) begin
            cnt_words_in_stream     <= 0;

        end else if ((hitmaker_dout_dv == 1'b1) && (state_wr != S_END_OF_STREAM)) begin
            cnt_words_in_stream     <= cnt_words_in_stream + 1;

        end
    end
        

    //----------------------------------------------------------------------------
    // State machine
    //----------------------------------------------------------------------------
    // Generate a series of hits:
    // Increment bitset from 0x0001 to 0xFFFF.
    // Set initial row and col to zero.
    // After each hit increment row from by 1 or 2.
    // If row equals row max then reset row and increase column by 2.
    // Start new stream after max hits. 
    // End last stream at row max, col max.
    //----------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin
        if (reset) begin

            sm_wr_ready         <= 1'b1;
		    state_wr            <= S_WR_IDLE;
            din_dv_cl           <= 1'b0;        // data valid to cluster generator         
            din_dv_lv           <= 1'b0;        // data valid to vertical line generator
            din_x               <= 8;           // column 
            din_y               <= 0;           // row
            din_bitset          <= 0;           // 16-bit (2x8) qrow block
            din_length          <= 0;           // line generator length (# of pixels)
            cnt_hits_in_stream  <= 1;
            
            sm_cnt_hitmap       <= 16'b0;       // Hitmap counter
            sm_dout_dv          <= 1'b0;        // Set when new incrementing hitmap produced  
            sm_dout_eos         <= 1'b0;        // Set at end-of-stream 
            sm_dout_eoe         <= 1'b0;        // Set at end-of-event
            cnt_stream_gap      <= 0;
            

        end else begin
        
            case (state_wr)
    
                //--------------------------------------------------------
                // Wait for start 
                //--------------------------------------------------------
    	        S_WR_IDLE : begin
    
                    if (start) begin

                        sm_wr_ready         <= 1'b0;
    	                state_wr            <= S_WR_INCR;

    	            end else begin   
                        sm_wr_ready         <= 1'b1;
                    end

                    cnt_hits_in_stream      <= 1;  
                    cnt_stream_gap          <= 0;
                    sm_cnt_hitmap           <= 16'h0;
                    sm_dout_dv              <= 1'b0;
                    sm_dout_eos             <= 1'b0;
                    sm_dout_eoe             <= 1'b0;
                    din_x                   <= 8;               // First qrow column
                    din_y                   <= 9'b111111110;    // row max - 2
                    hold_hits_per_stream    <= hits_per_stream;
                    hold_words_per_stream   <= words_per_stream;
                    
    	        end
    
    
                //--------------------------------------------------------
                // Generate hits with incrementing hitmap value from 0x0001 to 0xFFFF
                // parameter X_MAX  = 400; 
                // parameter Y_MAX  = 384; 
                //--------------------------------------------------------
    	        S_WR_INCR : begin

                    if (ready == 1'b1) begin

                        // End event but don't end stream . Only reset hitmap and x,y
                        if (sm_cnt_hitmap == C_LAST_HITMAP) begin                           // End of stream, end of event
                            sm_cnt_hitmap       <= 1;

                        end else begin
                            if (sm_cnt_hitmap == 16'hFFFF) begin
                                sm_cnt_hitmap       <= 1;
                            end else begin
                                sm_cnt_hitmap       <= sm_cnt_hitmap + 1;
                            end
                        end

                        if (cnt_hits_in_stream >= hold_hits_per_stream) begin      // End of a stream
                            state_wr            <= S_END_OF_STREAM;
                            cnt_hits_in_stream  <= 1;
                            sm_dout_eos         <= 1'b1;
                            sm_dout_eoe         <= 1'b0;
                        end else if (cnt_words_in_stream >= hold_words_per_stream) begin    // End of a stream
                            state_wr            <= S_END_OF_STREAM;
                            cnt_hits_in_stream  <= 0;       // Reset hit counter. Word counter is reset in its own process
                            sm_dout_eos         <= 1'b1;
                            sm_dout_eoe         <= 1'b0;
                        end else begin
                            cnt_hits_in_stream  <= cnt_hits_in_stream + 1;
                            sm_dout_eos         <= 1'b0;
                            sm_dout_eoe         <= 1'b0;
                        end

                        sm_dout_dv      <= 1'b1;
                    

                        // Output next qrow block (jump 2 pixels)
                        if (select_qrow_incr == 1'b0) begin

                            if (din_y == Y_MAX - 2) begin       // End of column. Reset row, increment col (by 8 pixels)
                                din_y   <= 0; 
                                if (din_x >= X_MAX)             // End of last column
                                    din_x   <= 8;
                                else
                                    din_x   <= din_x + 8;

                            end else begin                      // Next qrow in column
                                din_y   <= din_y + 2; 
                            end

                        // Skip next qrow block (jump 4 pixels)
                        end else begin 

                            if (din_y == Y_MAX - 4) begin       // End of column. Reset row, increment col (by 8 pixels)
                                din_y   <= 0; 
                                if (din_x >= X_MAX)             // End of last column
                                    din_x   <= 8;
                                else
                                    din_x   <= din_x + 8;

                            end 
                            else if (din_y == Y_MAX - 2) begin  // End of column. Start one qrow down on next col
                                din_y   <= 2; 

                                if (din_x >= X_MAX)             // End of last column
                                    din_x   <= 8;
                                else
                                    din_x   <= din_x + 8;

                            end else begin                      // Next qrow in column
                                din_y   <= din_y + 4; 
                            end

                        end

                    end else begin
                        sm_dout_dv      <= 1'b0;
                        sm_dout_eos     <= 1'b0;
                        sm_dout_eoe     <= 1'b0;
                    end
                end
                     

                //--------------------------------------------------------
                // If downstream FIFOs are getting full then the S.M. 
                // will pause hit generation. Updates the number of hits
                // per stream when the end of stream is reached.
                //--------------------------------------------------------
    	        S_END_OF_STREAM : begin

                    if (enable == 1'b0) begin    // End output 
    	                state_wr        <= S_WR_IDLE;
                    
                    end else if ((ready == 1'b1) && (cnt_stream_gap >= C_STREAM_GAP)) begin    // Resume output after a delay
                        cnt_stream_gap  <= 0;
     	                state_wr        <= S_WR_INCR;
                                      
                    end else begin
                        cnt_stream_gap <= cnt_stream_gap + 1;
                    end
                    
                    sm_dout_dv           <= 1'b0;
                    sm_dout_eos          <= 1'b0;
                    sm_dout_eoe          <= 1'b0;
                    
                    // Allow stream size updates to take effect
                    hold_hits_per_stream    <= hits_per_stream;   
                    hold_words_per_stream   <= words_per_stream;
                end


                //--------------------------------------------
                //--------------------------------------------
    	        default : begin
                    state_wr            <= S_WR_IDLE;
                    sm_dout_dv          <= 1'b0;
                    sm_dout_eos         <= 1'b0;
                    sm_dout_eoe         <= 1'b0;
    	        end

            endcase
        end
    end
    
    assign dout_dv          = sm_dout_dv;       //  Set when new dout_hit produced  
    assign dout_eos         = sm_dout_eos;      //  Set for end-of-stream. Last hit in stream
    assign dout_eoe         = sm_dout_eoe;      //  Set for end-of-event. Last hit in event
        
    assign dout_hit_ccol    = din_x[8:3];       //    
    assign dout_hit_qrow    = din_y[8:1];       //    
    assign dout_hit_hitmap  = sm_cnt_hitmap;    //   

    assign busy             = ~sm_wr_ready;     // Status output 


    //----------------------------------------------------------------------------
    // Random data used for setting cluster and line generator parameters
    //----------------------------------------------------------------------------
    rand32  u_rand32 
    (
        .clk        ( clk           ),  // input   logic           
        .reset      ( reset         ),  // input   logic           
        .restart    ( 1'b0          ),  // input   logic           
        .seed       ( seed          ),  // input   logic   [31:0]  
        .step       ( 1'b1          ),  // input   logic           
  
        .dout       ( random_dout   ),  // output  logic   [31:0]  
        .new_data   (               )   // output  reg             
    );


endmodule

