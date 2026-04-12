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
// Description: Non-debouncing 'debounce' block for simulation use
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
    
   
    // Simple pipeline delay instead of debounce
    always_ff @(posedge clk) begin
        if (reset) begin
            sw_out <= 0;
        end
        else begin
           sw_out <= sw_in;
        end
    end

endmodule
