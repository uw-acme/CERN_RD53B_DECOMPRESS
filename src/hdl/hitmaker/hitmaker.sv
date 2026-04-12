//----------------------------------------------------------------------------
// Top level hit maker.
// Intended for CPU control
//----------------------------------------------------------------------------
`timescale 1ns / 1ps


module hitmaker
(
    input   logic           clk                 ,  
    input   logic           reset               , 

    input   logic           enable              , // Allow stream generation
    input   logic           start               , // Begin stream generation
    output  logic           ready_out           , // Normally high. Goes low when any internal FIFO is over-threshold
    output  logic           busy                , // Set low when din_dv=1 then high after last dout of an event   

    // Control parameters
    input   logic   [ 1:0]  reg_mode_evgen      , // Type of data 00 = incrementing hitmap, 01 = 3x3 clusters, 10 cluster + vertical line, 11 cluster+vert+horiz lines
    input   logic   [31:0]  reg_seed            , // Seed to initialize the pseudo-random number generator
    input   logic   [15:0]  reg_hits_per_stream , 
    input   logic   [15:0]  reg_words_per_stream, 

    input   logic   [ 4:0]  reg_lv_density      , // Parameter to set the probability of a vertical line of hits occurring. Can be zero
    input   logic   [ 4:0]  reg_lv_maxlen       , // Parameter to set the max length of a v-line of hits occurring
    input   logic   [11:0]  reg_cl_density      , // Parameter to set the range of the increment in x,y from one cluster to the next.
    input   logic   [11:0]  reg_cl_max          , // Parameter to set the max number of clusters+lines to generate.
    input   logic           reg_restart         , // 
    input   logic           reg_en_encode       , // '1' = Encode (Compress) din. '0' = dout is din, dout_size = 16 (5'b1000)
    input   logic           reg_en_tot          , // '1' = ToT enabled, '0'= No ToT data
    input   logic           reg_mode_tot        , // '0' = Constant (tot_value), '1' = Incrementing
    input   logic   [ 3:0]  reg_tot_value       , //  ToT value for constant mode
    input   logic   [ 7:0]  reg_tag_init        , //  Tag to start output stream. Subsequent tags (internal) will be 11-bit
    input   logic   [ 1:0]  reg_chip_id         , //  
    input   logic           reg_en_chip_id      , //  Enable chip ID[1:0]
    input   logic           reg_en_eos          , //  Enable min 6 zeros output to mark end of stream

    // Output of raw event generator data, for comparison with resulting data after encoding then decoding 
    output  logic           hit_dv              , // 
    output  logic           hit_eos             , //  
    output  logic           hit_eoe             , // 
    output  logic   [ 7:0]  hit_qrow            , // 
    output  logic   [ 5:0]  hit_ccol            , // 
    output  logic   [15:0]  hit_hitmap          , // 

    // Output of ToT data, for comparison with resulting data after encoding then decoding 
    output  logic           hit_tot_dv          , // 
    output  logic           hit_tot_eos         , // 
    output  logic   [63:0]  hit_tot             , // 
    output  logic   [ 6:0]  hit_tot_size        , // Number of bits in dout

    // Output interface
    input   logic           ready_in            , //  Normally high from downstream sink. Goes low when sink cannot accept data
    output  logic           dout_ns             , //  New stream bit (Bit-63 of Aurora data word)
    output  logic   [62:0]  dout                , //  Data 
    output  logic           dout_eos            , //  Set for end-of-stream. Last hit in stream 
    output  logic           dout_eoe            , //  Set for end-of-event. Last hit in event
    output  logic           dout_dv               //  Set when new dout produced  
);

    logic           evgen_busy        ;    // Event generator is producing an events-worth of output  
    logic           evgen_dout_dv     ;    // Set when new dout_hit produced  
    logic           evgen_dout_eos    ;    // Set for end-of-stream. Last hit in stream 
    logic           evgen_dout_eoe    ;    // Set for end-of-event. Last hit in event
    logic   [ 7:0]  evgen_dout_qrow   ;    // 
    logic   [ 5:0]  evgen_dout_ccol   ;    // 
    logic   [15:0]  evgen_dout_hitmap ;    // 

    logic   [15:0]  addr_dout         ;    // Output data.  
    logic   [ 4:0]  addr_dout_size    ;    // Number of bits in dout (2 to 16)
    logic           addr_dout_dv      ;    // Output data valid
    logic           addr_dout_eos     ;    // Output EOS
    logic           addr_dout_eoe     ;    // Output EOE

    logic   [29:0]  encode_dout       ;    // Output data. Encoded hitmap (in MSBs)
    logic   [ 4:0]  encode_dout_size  ;    // Number of bits in encoded hitmap
    logic           encode_dout_eos   ;    // Output data end-of-stream
    logic           encode_dout_dv    ;    // Output data valid

    logic   [63:0]  tots_dout         ;    // Output data. Up to 16 4-bit ToT values (in MSBs)
    logic   [ 6:0]  tots_dout_size    ;
    logic           tots_dout_eos     ;    // Output data end-of-stream
    logic           tots_dout_dv      ;    // Output data valid

    logic  [109:0]  pack_dout         ;    // Output data. 
    logic   [ 6:0]  pack_dout_size    ;    // Number of bits in all hit fields
    logic           pack_dout_eos     ;    // data end-of-stream
    logic           pack_dout_eoe     ;    // data end-of-event
    logic           pack_dout_dv      ;    // data valid

    logic           assem_ready       ;    // Assembler ready for data
    logic           evgen_ready_in    ;    // Downstream blocks can accept event generator data

    assign addr_dout_eoe = 1'b0;    // TODO : pipeline through hit_addr
    
    assign evgen_ready_in   = ready_in & assem_ready;

    //----------------------------------------------------------------------------
    // Event generator
    //----------------------------------------------------------------------------
    event_gen               u_event_gen
    (
        .clk                ( clk                   ),  // input             
        .reset              ( reset                 ),  // input             

        .enable             ( enable                ), // input             Allow stream generation
        .start              ( start                 ), // input             Begin stream generation
        .ready              ( evgen_ready_in        ), // input             Downstream blocks can accept new hit data
        .busy               ( evgen_busy            ), // output            Set low when din_dv=1 then high on last dout of event  

        .seed               ( reg_seed              ), // input     [31:0]  Seed to initialize the pseudo-random number generator

        // Controls for stream size. The first condition to be reached, terminates each stream
        .hits_per_stream    ( reg_hits_per_stream   ), // input     [15:0]  
        .hitmaker_dout_dv   ( dout_dv               ), // input             Set high when hitmaker block outputs a new word
        .words_per_stream   ( reg_words_per_stream  ), // input     [15:0]  

        // Output raw hit
        .dout_dv            ( evgen_dout_dv         ), // output            Set when new dout_hit produced  
        .dout_eos           ( evgen_dout_eos        ), // output            Set for end-of-stream. Last hit in stream 
        .dout_eoe           ( evgen_dout_eoe        ), // output            Set for end-of-event. Last hit in event 
        .dout_hit_qrow      ( evgen_dout_qrow       ), // output    [ 7:0]  
        .dout_hit_ccol      ( evgen_dout_ccol       ), // output    [ 5:0]  
        .dout_hit_hitmap    ( evgen_dout_hitmap     )  // output    [15:0]  
    );

    // Drive original unencoded hit data to outputs to be used to compare against data after encoding and decoding has been done
    assign hit_dv           = evgen_dout_dv     ;    
    assign hit_eos          = evgen_dout_eos    ;     
    assign hit_eoe          = evgen_dout_eoe    ;    
    assign hit_qrow         = evgen_dout_qrow   ;    
    assign hit_ccol         = evgen_dout_ccol   ;    
    assign hit_hitmap       = evgen_dout_hitmap ;    

    assign busy             = evgen_busy;

    //----------------------------------------------------------------------------
    // Encode the address section of hit data (qrow, ccol, islast, is_neighbor)
    //----------------------------------------------------------------------------
    hit_addr                u_hit_addr
    (
        .clk                ( clk                   ),   // input           
        .reset              ( reset                 ),   // input           

        .din_qrow           ( evgen_dout_qrow       ),   // input   [ 7:0]   
        .din_ccol           ( evgen_dout_ccol       ),   // input   [ 5:0]   
        .din_eos            ( evgen_dout_eos        ),   // input            Input data end-of-stream. Used to flush hits
        .din_dv             ( evgen_dout_dv         ),   // input            Input data valid

        .dout               ( addr_dout             ),   // output  [15:0]   Output data.  
        .dout_size          ( addr_dout_size        ),   // output  [ 4:0]   Number of bits in dout (2 to 16)
        .dout_eos           ( addr_dout_eos         ),   // output           Output EOS
        .dout_dv            ( addr_dout_dv          )    // output           Output data valid
    );


    //----------------------------------------------------------------------------
    // Encode a hitmap (2x8 Pixels) into a 4-bit to 30-bit value
    //----------------------------------------------------------------------------
    hit_encode              u_hit_encode
    (
        .clk                ( clk                   ) ,   // input         
        .reset              ( reset                 ) ,   // input         
        .en_encode          ( reg_en_encode         ) ,   // input          '1' = Encode (Compress) din. '0' = dout is din, dout_size = 16 (5'b1000)

        .din                ( evgen_dout_hitmap     ) ,   // input   [15:0] Input data, 8x2 hitmap
        .din_eos            ( evgen_dout_eos        ) ,   // input          Input data end-of-stream. Used to flush hits
        .din_dv             ( evgen_dout_dv         ) ,   // input          Input data valid

        .dout               ( encode_dout           ) ,   // output  [29:0] Output data. Encoded hitmap (in MSBs)
        .dout_size          ( encode_dout_size      ) ,   // output  [ 4:0] Number of bits in encoded hitmap
        .dout_eos           ( encode_dout_eos       ) ,   // output         Output data end-of-stream
        .dout_dv            ( encode_dout_dv        )     // output         Output data valid
    );

    //----------------------------------------------------------------------------
    // Use number of bits set in hitmap to create bus of 1 to 16 
    // 4-bit 'time-over-threshold' (ToT) values 
    //----------------------------------------------------------------------------
    hit_tots                u_hit_tots
    (
        .clk                ( clk                   ),   // input           
        .reset              ( reset                 ),   // input           

        .en_tot             ( reg_en_tot            ),   // input            '1' = ToT enabled, '0'= No ToT data
        .mode_tot           ( reg_mode_tot          ),   // input            '0' = Constant (tot_value), '1' = Incrementing
        .tot_value          ( reg_tot_value         ),   // input   [ 3:0]   ToT value for constant mode

        .din                ( evgen_dout_hitmap     ),   // input   [15:0]   Input data, 8x2 hitmap
        .din_eos            ( evgen_dout_eos        ),   // input            Input data end-of-stream. Used to flush hits
        .din_dv             ( evgen_dout_dv         ),   // input            Input data valid

        .dout               ( tots_dout             ),   // output  [63:0]   Output data. Up to 16 4-bit ToT values (in MSBs)
        .dout_size          ( tots_dout_size        ),   // output  [ 6:0]   Number of bits in dout
        .dout_eos           ( tots_dout_eos         ),   // output           Output data end-of-stream
        .dout_dv            ( tots_dout_dv          )    // output           Output data valid
    );
    
    assign  hit_tot_size = tots_dout_size; // output  [ 6:0]   Output Tot size. Up to 64 bits in ToT output
    assign  hit_tot      = tots_dout     ; // output  [63:0]   Output ToT data. Up to 16 4-bit ToT values (in MSBs)
    assign  hit_tot_eos  = tots_dout_eos ; // output           Output ToT EOS. Marks last ToT of current stream
    assign  hit_tot_dv   = tots_dout_dv  ; // output           Output ToT data valid

    // Data from encoder, addr and ToT blocks is delayed until their pipelines fit.
    // the problem is that addr[n] cannot be output until addr[n+1] is seen because of the is_last bit.
    // Each block has a 3-stage pipelinebut the pipeline must be filled before any output occurs.


    //----------------------------------------------------------------------------
    // Pack the hit_addr, hit_encode and hit_tot output buses into the MSBs 
    // of one 16 to 110 bit bus
    //----------------------------------------------------------------------------
    hit_packer              u_hit_packer
    (
        .clk                ( clk                   ),   // input            
        .reset              ( reset                 ),   // input            

        .din_addr           ( addr_dout             ),   // input    [15:0]   Compressed address (in MSBs)
        .din_addr_size      ( addr_dout_size        ),   // input    [ 4:0]   Number of bits in compressed address

        .din_hitmap         ( encode_dout           ),   // input    [29:0]   Encoded hitmap (in MSBs)
        .din_hitmap_size    ( encode_dout_size      ),   // input    [ 4:0]   Number of bits in encoded hitmap

        .din_tots           ( tots_dout             ),   // input    [63:0]   Up to 16 4-bit ToT values (in MSBs)
        .din_tots_size      ( tots_dout_size        ),   // input    [ 6:0]   Number of bits in ToT bus

        // Use dv, eos,eoe from hit_addr
        .din_eos            ( addr_dout_eos         ),   // input             Input data end-of-stream.  Passed through
        .din_eoe            ( addr_dout_eoe         ),   // input             Input data end-of-event.  Passed through
        .din_dv             ( addr_dout_dv          ),   // input             Input data valid

        .dout               ( pack_dout             ),   // output  [109:0]   Output data. 
        .dout_size          ( pack_dout_size        ),   // output   [ 6:0]   Number of bits in all hit fields
        .dout_eos           ( pack_dout_eos         ),   // output            Output data end-of-sequence
        .dout_eoe           ( pack_dout_eoe         ),   // output            Output data end-of-sequence
        .dout_dv            ( pack_dout_dv          )    // output            Output data valid
    );


    //----------------------------------------------------------------------------
    // Build 64-bit Aurora output words from variable size packed {addr,hit,tot} 63-bit data.
    //  Add 'NS' (new stream) flags, chip ID, increment tag number.
    //  Insert orphan bits at end-of-stream. 
    //  Generate internal tag if column address wraps to 1 (meaning that the data is from a new event)
    //----------------------------------------------------------------------------
    hit_assembler           u_hit_assembler
    (
        .clk                ( clk                   ),   // input            
        .reset              ( reset                 ),   // input
        
        .restart            ( reg_restart           ),   // input            
        .tag_init           ( reg_tag_init          ),   // input    [ 7:0]   Tag to start output stream. Subsequent tags (internal) will be 11-bit
        .chip_id            ( reg_chip_id           ),   // input    [ 1:0]   
        .en_chip_id         ( reg_en_chip_id        ),   // input             Enable chip ID[1:0]
        .en_eos             ( reg_en_eos            ),   // input             Enable min 6 zeros output to mark end of stream

        .din                ( pack_dout             ),   // input   [109:0]   Hit data in MSBs (addr,hitmap,ToTs)
        .din_size           ( pack_dout_size        ),   // input    [ 6:0]   Number of valid bits in din
        .din_eos            ( pack_dout_eos         ),   // input             Input data end-of-stream.  Passed through
        .din_eoe            ( pack_dout_eoe         ),   // input             Input data end-of-stream.  Passed through
        .din_dv             ( pack_dout_dv          ),   // input             Input data valid

        .ready_out          ( assem_ready           ),   // output            Normally high. Goes low when either internal FIFO is over-threshold
        .ready_in           ( 1'b1                  ),   // input             Normally high from downstream sink. Goes low when sink cannot accept data
        .dout               ( dout                  ),   // output   [62:0]   Output data. 
        .dout_eos           ( dout_eos              ),   // output            Output EOS
        .dout_eoe           ( dout_eoe              ),   // output            Output EOE
        .dout_ns            ( dout_ns               ),   // output            Output 'new stream'
        .dout_dv            ( dout_dv               )    // output            Output data valid
    );

    assign ready_out = assem_ready;

endmodule
