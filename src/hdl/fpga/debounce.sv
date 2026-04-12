`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/15/2021 08:54:12 PM
// Design Name: 
// Module Name: debounce
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// takes switch input, syncs to clock, and debounces 
module debounce(
    input   logic clk,
    input   logic reset,
    input   logic sw_in,
    output  logic sw_out
    );
    
    // for metastability
    logic sw_msync0;
    logic sw_msync1;
    
    // for short shift register
    logic [4:0] short_shift;
    logic short_shifted;
    
    // for debouncing
    logic [15:0] cnt_stable;
    logic idle;
    assign idle = sw_out == (short_shift[0]);
    logic cnt_max;
    assign cnt_max = &cnt_stable;
    
    // filter out metastability
    always_ff @(posedge clk) begin
        sw_msync0 <= sw_in;
        sw_msync1 <= sw_msync0;
    end
    
    // short shift register
    integer i;
    always_ff @(posedge clk) begin
        if (reset)
            short_shift <= 5'b00000;
        else begin
            for (i=0; i<4; i++) begin
                short_shift[i] <= short_shift[i+1];
            end
            if (sw_msync1)
                short_shift[4] <= 1;
            else
                short_shift[4] <= 0;
        end
    end
    assign short_shifted = &short_shift | !(|short_shift);
    
    // debounce
    always_ff @(posedge clk) begin
        if (reset) begin
            sw_out <= 0;
        end
        else begin
            if (short_shifted) begin
                if (idle) begin
                    cnt_stable <= 0;
                end
                else begin
                    cnt_stable <= cnt_stable + 1'b1;
                end
                if (cnt_max) begin
                    sw_out <= ~sw_out;
                end
            end
        end
    end

endmodule
