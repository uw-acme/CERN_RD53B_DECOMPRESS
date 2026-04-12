//----------------------------------------------------------------------------
// Pseudo-randomdo-random number gnerator using a 32-bit linear feedback shift register
//----------------------------------------------------------------------------
`timescale 1ns / 1ps

module rand32 
(   
    input   logic           clk     ,
    input   logic           reset   , 
    input   logic           restart , 
    input   logic   [31:0]  seed    , 
    input   logic           step    ,
    
    output  logic   [31:0]  dout    ,
    output  reg             new_data
);

    reg [31:0] lfsr;    // Shift register
    
    
    //------------------------------------------------------------------------
    // Linear Feedback Shift Register
    //------------------------------------------------------------------------
    always @(posedge clk)
    begin
        if (reset | restart)
        begin
        
            lfsr[31:0]  <= seed[31:0];
            new_data    <= 1'b0;
            
        end else if (step) 
        begin
        
            new_data    <= 1'b1;
            
            lfsr[23:0]  <= lfsr[24:1];
            lfsr[24]    <= lfsr[25] ^ lfsr[0];
            lfsr[25]    <= lfsr[26] ^ lfsr[0];
            lfsr[28:26] <= lfsr[29:27];
            lfsr[29]    <= lfsr[30] ^ lfsr[0];
            lfsr[30]    <= lfsr[31];
            lfsr[31]    <= lfsr[0];
            
        end else 
        begin
        
            new_data    <= 1'b0;
            
        end
    end
 
    assign dout = lfsr;


endmodule
