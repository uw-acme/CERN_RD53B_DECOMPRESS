//----------------------------------------------------------------------------------------------------------------------
// [Filename]       hit_addr.sv [RTL]
// [Project]        RD53B emulator
// [Author]         
// [Language]       SystemVerilog 2012 [IEEE Std. 1800-2012]
// [Created]        
// [Description]    Encode the address section of hit data (qrow, ccol, is_last, is_neighbor)  
//                  Three stage pipeline
//----------------------------------------------------------------------------------------------------------------------
`ifndef HIT_ADDR__SV
`define HIT_ADDR__SV

`timescale 1ns / 1ps


//----------------------------------------------------------------------------------------------------------------------------------
module hit_addr
(
    input   logic           clk         ,
    input   logic           reset       ,

    input   logic   [ 7:0]  din_qrow    ,   // 
    input   logic   [ 5:0]  din_ccol    ,   // 
    input   logic           din_eos     ,   // Input data end-of-stream. Used to flush hits
    input   logic           din_dv      ,   // Input data valid
    
    output  logic   [15:0]  dout        ,   // Output data.  
    output  logic   [ 4:0]  dout_size   ,   // Number of bits in dout (2 to 16)
    output  logic           dout_eos    ,   // Output EOS
    output  logic           dout_dv         // Output data valid
);

    //--------------------------------------------------------------------------------------
    // Input is ccol and qrow
    //
    // Output can have ccol, is_last, is_neighbor and qrow
    // qrow and/or ccol can be omitted, depending on the setting of is_last and is_neigbor
    //
    //  Full output   ccol[5:0], is_last, is_neighbor, qrow[7:0]    = 16 bits
    //
    // If is_last is set then ccol is included in the NEXT hit output.
    // If is_last is zero then ccol can be omitted from the current hit output
    //  Reduced     : is_last, is_neighbor, qrow[7:0]               = 10 bits
    //
    // If is_neighbor is set then qrow can be omitted from the current hit output
    //  Reduced     : ccol[5:0], is_last, is_neighbor,              =  8 bits
    //
    // If is_neighbor is set and is_last is zero then qrow and ccol can be omitted from the current hit output
    //  Reduced     : is_last, is_neighbor,                         =  2 bits
    //
    //--------------------------------------------------------------------------------------

    // Pipeline regs
    logic   [ 7:0]  qrow_d1, qrow_d2;
    logic   [ 5:0]  ccol_d1, ccol_d2;
    logic           dv_d1, dv_d2;
    logic           new_stream, new_stream_d1, new_stream_d2;
    //logic           is_last_d1;
    logic           is_last_d2;
    logic           is_last_d3;
    logic           is_neighbor_d1, is_neighbor_d2;
    logic           eos_d1, eos_d2;

    // Debug signals
    logic   [ 5:0]  debug_ccol; 
    logic           debug_islast; 
    logic           debug_isneighbor; 
    logic   [ 7:0]  debug_qrow; 
    logic           debug_dv; 
   
    //--------------------------------------------------------------------------------------
    // 3-stage pipeline to match hitmap encoder delay
    //--------------------------------------------------------------------------------------
    always_ff @(posedge clk) 
    begin

        if (reset) begin

            new_stream      <= 1'b1;
            new_stream_d1   <= 1'b1;
            new_stream_d2   <= 1'b1;

            eos_d1          <= 1'b0;
            eos_d2          <= 1'b0;

            dv_d1           <= 1'b0;
            dv_d2           <= 1'b0;

            qrow_d1         <= 8'b11111110;
            qrow_d2         <= 8'b11111110;

            ccol_d1         <= 6'b111110;
            ccol_d2         <= 6'b111110;

            is_last_d2      <= 1'b1;
            is_last_d3      <= 1'b1;

            is_neighbor_d1  <= 1'b0;
            is_neighbor_d2  <= 1'b0;
        
            dout            <= 16'b0; 
            dout_size       <= 5'b0;  
            dout_dv         <= 1'b0;

        end else begin

            new_stream_d1  <= new_stream;
            new_stream_d2  <= new_stream_d1;

            eos_d1  <= din_eos & din_dv;
            eos_d2  <= eos_d1;

            //------------------------------------------------------------------------------
            // Advance pipeline on 'din_dv' and also generate two internal pipe shifts after
            // a 'din_eos' to flush the pipeline.
            //------------------------------------------------------------------------------
            if (din_dv | eos_d1 | eos_d2) begin    

                //------------------------------------------------------------------------------
                // First stage pipeline 
                //------------------------------------------------------------------------------
                dv_d1       <= din_dv;
                qrow_d1     <= din_qrow;
                ccol_d1     <= din_ccol;

                // Set 'is_neighbor' if row has incremented
                if (din_qrow == qrow_d1 + 1) 
                    is_neighbor_d1  <= 1'b1;
                else
                    is_neighbor_d1  <= 1'b0;



                //------------------------------------------------------------------------------
                // Second stage
                //------------------------------------------------------------------------------
                dv_d2           <= dv_d1;
                qrow_d2         <= qrow_d1;
                ccol_d2         <= ccol_d1;
                is_neighbor_d2  <= is_neighbor_d1;
                is_last_d3      <= is_last_d2;

                // Set 'is_last' on previous column if current if column is different from previous column or eos is set
                if ((din_ccol != ccol_d1) || (eos_d1 == 1'b1)) 
                    is_last_d2  <= 1'b1;
                else
                    is_last_d2  <= 1'b0;


                //------------------------------------------------------------------------------
                // Third stage
                // Output data
                //------------------------------------------------------------------------------
                // First output of a stream, output all fields with is_neighbor low
                if      (new_stream_d2 == 1'b1) begin   
                    dout        <= {ccol_d2, is_last_d2,          1'b0, qrow_d2};   
                    dout_size   <= 5'b10000;                                        // 16 bits always on first output hit of a stream
                end 

                else if ((is_last_d3 == 1'b1) && (is_neighbor_d2 == 1'b0)) begin    // All fields
                    dout        <= {ccol_d2, is_last_d2, is_neighbor_d2, qrow_d2};   
                    dout_size   <= 5'b10000;                                        // 16 bits
                end 

                else if ((is_last_d3 == 1'b0) && (is_neighbor_d2 == 1'b0)) begin    // No ccol needed 
                    dout        <= {         is_last_d2, is_neighbor_d2,  qrow_d2, 6'b0};        
                    dout_size   <= 5'b01010;                                        // 10 bits
                end

                else if ((is_last_d3 == 1'b1) && (is_neighbor_d2 == 1'b1)) begin    // No qrow needed
                    dout        <= {ccol_d2, is_last_d2, is_neighbor_d2, 8'b0}; 
                    dout_size   <= 5'b01000;                                        // 8 bits
                end

                else if ((is_last_d3 == 1'b0) && (is_neighbor_d2 == 1'b1)) begin    // No ccol or qrow
                    dout        <= {         is_last_d2, is_neighbor_d2, 14'b0}; 
                    dout_size   <= 5'b00010;                                        // 2 bits
                end
            
                // Pipeline delays for data valid
                dout_dv     <= dv_d2;
                dout_eos    <= eos_d2;


                // Clear 'new_stream' on first output. Set it again after 'end-of-stream' output
                if ((new_stream_d2 == 1'b1) && (eos_d2 == 1'b0)) begin   
                    new_stream  <= 1'b0;
                end else if (eos_d2 == 1'b1) begin
                    new_stream  <= 1'b1;
                end 

            end else begin

                dout        <= 16'b0; 
                dout_size   <= 5'b0;  
                dout_eos    <= 1'b0;
                dout_dv     <= 1'b0;

            end
        end
    end 
    


    //--------------------------------------------------------------------------------------
    // Debug address encoding
    //--------------------------------------------------------------------------------------
    always_comb 
    begin

        if (reset) begin

            debug_ccol          = 6'bx; 
            debug_islast        = 1'bx; 
            debug_isneighbor    = 1'bx; 
            debug_qrow          = 8'bx; 
            debug_dv            = 1'bx; 

        end else begin

        if (dout_dv == 1'b1) begin
            
                debug_dv        = 1'b1; 
                case(dout_size)
                    5'b00010 :  begin   // 2 bit. islast, isneighbor
                                    debug_ccol          = 6'bx; 
                                    debug_islast        = dout[15]; 
                                    debug_isneighbor    = dout[14]; 
                                    debug_qrow          = 8'bx; 
                                end 
                    
                    5'b01000 :  begin   // 8 bit.  ccol, islast, isneighbor, 
                                    debug_ccol          = dout[15:10]; 
                                    debug_islast        = dout[9]; 
                                    debug_isneighbor    = dout[8]; 
                                    debug_qrow          = 8'bx; 
                                end
                                    
                    5'b01010 :  begin   // 10 bit. islast, isneighbor, qrow
                                    debug_ccol          = 6'bx; 
                                    debug_islast        = dout[15]; 
                                    debug_isneighbor    = dout[14]; 
                                    debug_qrow          = dout[13:6]; 
                                end
                    
                    5'b10000 :  begin   // 16 bit. ccol, islast, isneighbor, qrow
                                    debug_ccol          = dout[15:10]; 
                                    debug_islast        = dout[9]; 
                                    debug_isneighbor    = dout[8]; 
                                    debug_qrow          = dout[7:0]; 
                                end
                    
                    default:    begin
                                    debug_ccol          = 6'bx; 
                                    debug_islast        = 1'bx; 
                                    debug_isneighbor    = 1'bx; 
                                    debug_qrow          = 8'bx;
                                end
                endcase

            end else begin
                debug_ccol          = 6'bx; 
                debug_islast        = 1'bx; 
                debug_isneighbor    = 1'bx; 
                debug_qrow          = 8'bx; 
                debug_dv            = 1'b0; 
            end
        end
    end

endmodule
    
`endif

