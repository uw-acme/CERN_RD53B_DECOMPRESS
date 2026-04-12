//----------------------------------------------------------------------------
// File : defines_rd53b.sv
//----------------------------------------------------------------------------
`ifndef DEFINES_RD53B__SV
`define DEFINES_RD53B__SV

// Number of pixels in X and Y directions
parameter X_MAX  = 400; 
//parameter Y_MAX  = 384; 
parameter Y_MAX  = 64;  // Reduced for debugging. Causes ccol to change more frequently

parameter CCOL_MAX = X_MAX/8;   // 50   (0 to  49, 0x0 to 0x31)
parameter QROW_MAX = Y_MAX/2;   // 192  (0 to 191, 0x0 to 0xBF)

// Type definition for a 'quarter row' block location and hit map contents
typedef struct packed {
    logic   [ 7:0]  qrow;       // 
    logic   [ 5:0]  ccol;       // 
    logic   [15:0]  bitmap;     // 
} t_hit;    

    
`endif

