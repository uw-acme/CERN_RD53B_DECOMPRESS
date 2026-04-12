-------------------------------------------------------------------------------
-- Author      : Gjones
-------------------------------------------------------------------------------
-- FPGA for testing RD53B output Aurora bus decoding.
-- Uses hitmaker block to generate patterns and compressed data.
-- Contains 1 decoders.
-- Compares decoded data against original data.
-------------------------------------------------------------------------------
library ieee;
use     ieee.std_logic_1164.all;
use     ieee.std_logic_misc.all;
use     ieee.numeric_std.all;
use     std.textio.all;

entity  fpga_KC705_enc_decode1 is
port(
    SYSCLK_P        : in    std_logic; 
    SYSCLK_N        : in    std_logic;
    CPU_RESET       : in    std_logic; 

    GPIO_SW_N       : in    std_logic; -- start
    GPIO_SW_S       : in    std_logic; -- stop
    GPIO_SW_E       : in    std_logic; -- 
    GPIO_SW_W       : in    std_logic; -- 
    GPIO_SW_C       : in    std_logic; -- 

    GPIO_DIP_SW0    : in    std_logic; -- for reg_hits_per_stream or reg_words_per_stream
    GPIO_DIP_SW1    : in    std_logic;
    GPIO_DIP_SW2    : in    std_logic;
    GPIO_DIP_SW3    : in    std_logic;

    GPIO_LED_0_LS   : out   std_logic; 
    GPIO_LED_1_LS   : out   std_logic;
    GPIO_LED_2_LS   : out   std_logic;
    GPIO_LED_3_LS   : out   std_logic;
    GPIO_LED_4_LS   : out   std_logic;
    GPIO_LED_5_LS   : out   std_logic;
    GPIO_LED_6_LS   : out   std_logic;
    GPIO_LED_7_LS   : out   std_logic;

    DEBUG_OUT       : out   std_logic_vector( 6 downto 0)    
);
end fpga_KC705_enc_decode1;

architecture struct_x1 of fpga_KC705_enc_decode1 is

constant NCHAN                  : integer := 8;

type t_arr_slv2               is array (0 to NCHAN-1) of std_logic_vector( 1 downto 0);
type t_arr_slv3               is array (0 to NCHAN-1) of std_logic_vector( 2 downto 0);
type t_arr_slv6               is array (0 to NCHAN-1) of std_logic_vector( 5 downto 0);
type t_arr_slv8               is array (0 to NCHAN-1) of std_logic_vector( 7 downto 0);
type t_arr_slv16              is array (0 to NCHAN-1) of std_logic_vector(15 downto 0);
type t_arr_slv64              is array (0 to NCHAN-1) of std_logic_vector(63 downto 0);

signal clk                      : std_logic := '0';             
signal reset                    : std_logic := '1';
signal clkreset_lock            : std_logic := '0';
signal brd_reset_in             : std_logic := '1';           
signal brd_switches             : std_logic_vector( 3 downto  0) ;  --

signal random_dout              : std_logic_vector(31 downto  0) ;  -- Output of pseudo-random number generator
signal random_seed              : std_logic_vector(31 downto  0) ;  -- Seed for pseudo-random number generator
signal btn_start                : std_logic;                        -- Debounced button
signal btn_stop                 : std_logic;                        -- Debounced button

signal hitmaker_enable          : std_logic ;                       -- Allow stream generation
signal hitmaker_start           : std_logic ;                       -- Begin stream generation
signal hitmaker_ready           : std_logic ;                       -- Normally high. Goes low when any internal FIFO is over-threshold
signal hitmaker_busy            : std_logic ;                       -- Set low when din_dv=1 then high after last dout of an event   

-- Control parameters
signal reg_mode_evgen           : std_logic_vector( 1 downto  0) ;  -- Type of data 00 = incrementing hitmap, 01 = 3x3 clusters, 10 cluster + vertical line, 11 cluster+vert+horiz lines
signal reg_seed                 : std_logic_vector(31 downto  0) ;  -- Seed to initialize the pseudo-random number generator
signal reg_hits_per_stream      : std_logic_vector(15 downto  0) ;  -- 
signal reg_words_per_stream     : std_logic_vector(15 downto  0) ;  -- 
signal reg_lv_density           : std_logic_vector( 4 downto  0) ;  -- Parameter to set the probability of a vertical line of hits occurring. Can be zero
signal reg_lv_maxlen            : std_logic_vector( 4 downto  0) ;  -- Parameter to set the max length of a v-line of hits occurring
signal reg_cl_density           : std_logic_vector(11 downto  0) ;  -- Parameter to set the range of the increment in x,y from one cluster to the next.
signal reg_cl_max               : std_logic_vector(11 downto  0) ;  -- Parameter to set the max number of clusters+lines to generate.
signal reg_restart              : std_logic                      ;  -- 
signal reg_en_encode            : std_logic                      ;  -- '1' = Encode (Compress) din. '0' = dout is din, dout_size = 16 (5'b1000)
signal reg_en_tot               : std_logic                      ;  -- '1' = ToT enabled, '0'= No ToT data
signal reg_mode_tot             : std_logic                      ;  -- '0' = Constant (tot_value), '1' = Incrementing
signal reg_tot_value            : std_logic_vector( 3 downto  0) ;  -- ToT value for constant mode
signal reg_tag_init             : std_logic_vector( 7 downto  0) ;  -- Tag to start output stream. Subsequent tags (internal) will be 11-bit
signal reg_chip_id              : std_logic_vector( 1 downto  0) ;  --  
signal reg_en_chip_id           : std_logic                      ;  -- Enable chip ID[1:0]
signal reg_en_eos               : std_logic                      ;  -- Enable min 6 zeros output to mark end of stream

---------------------------------------------------------------
-- Hitmaker output
-- 'Expected' data
-- Original event generator data, for comparison with resulting 
-- data after encoding then decoding 
---------------------------------------------------------------
signal exp_hit_eos              : std_logic                      ;              
signal exp_hit_eoe              : std_logic                      ;             
signal exp_hit_qrow             : std_logic_vector( 7 downto  0) ;    
signal exp_hit_ccol             : std_logic_vector( 5 downto  0) ;    
signal exp_hit_hitmap           : std_logic_vector(15 downto  0) ;    
signal exp_hit_dv               : std_logic                      ;             
signal exp_hit_tot              : std_logic_vector(63 downto  0) ;  -- hitmaker ToT data
signal exp_hit_tot_size         : std_logic_vector( 6 downto  0) ;  -- hitmaker ToT data size
signal exp_hit_tot_eos          : std_logic                      ;  -- ToT end-of-stream
signal exp_hit_tot_dv           : std_logic                      ;  -- expected tot data valid
signal exp_hitmap_reversed      : std_logic_vector(15 downto 0)  ;  -- Input data, 8x2 hitmap

-- Output of encoded data                  
signal hitmaker_ready_in        : std_logic;
signal hitmaker_dout            : std_logic_vector( 62 downto 0);   --  Output data. 
signal hitmaker_dout_eos        : std_logic;                        --  
signal hitmaker_dout_eoe        : std_logic;                        --  
signal hitmaker_dout_ns         : std_logic;                        --  
signal hitmaker_dout_dv         : std_logic;                        --  Output data valid

-- Stream data distributor status outputs 
signal dist_strm_busy           : std_logic;                        -- Status. Set once a 'NS=1' is seen. Cleared when all decoders are not busy

-- Stream data distributor outputs to expected data distributor
signal dist_strm_chan           : std_logic_vector( 2 downto 0);    -- Encoded data channel number (0-7)
signal dist_strm_chan_dv        : std_logic;                        -- New stream channel data valid
signal dist_strm_drop           : std_logic;                        -- Distrib_stream is telling distrib_exp that it is dropping current stream

-- Distrib_stream outputs to decoders. Only one channel is active at a time
signal dist_strm_dout           : std_logic_vector(62 downto 0);    -- Input encoded stream data
signal dist_strm_dout_ns        : std_logic;                        -- NS (new_stream) bit
signal dist_strm_dout_chan      : std_logic_vector( 2 downto 0);    -- Encoded data channel number (0-7)
signal dist_strm_dout_dvs       : std_logic_vector( 7 downto 0);    -- Data valids
                         
-- Distributor for un-encoded event generator data to hit_checkers for comparison with data after decoding.
-- Common bus to all hit_checkers. One bit in dist_exp_dvs selects the destination hit_checker.
signal dist_exp_busy            : std_logic;                        -- Status. Set once a 'NS=1' is seen. Cleared when all decoders are not busy
signal dist_exp_status          : std_logic_vector( 7 downto 0);    -- Status. FIFO overflows etc.
signal dist_exp_eos             : std_logic;  
signal dist_exp_eoe             : std_logic; 
signal dist_exp_qrow            : std_logic_vector( 7 downto 0); 
signal dist_exp_ccol            : std_logic_vector( 5 downto 0); 
signal dist_exp_hitmap          : std_logic_vector(15 downto 0); 
signal dist_exp_chan            : std_logic_vector( 2 downto 0);    -- Encoded data channel number (0-7)
signal dist_exp_tot             : std_logic_vector(63 downto 0);    -- ToT data packed into MSBs of bus
signal dist_exp_tot_size        : std_logic_vector( 6 downto 0);
-- One bit to each hit_checker
signal dist_exp_dvs             : std_logic_vector( 7 downto 0);    -- Expected data valid


---------------------------------------------------------------
-- Decoders output of decoded hit data fields
---------------------------------------------------------------
signal arr_decoder_chip_id      : t_arr_slv2;
signal arr_decoder_tag          : t_arr_slv8;
signal arr_decoder_eos          : std_logic_vector(NCHAN-1 downto 0);              
signal arr_decoder_eoe          : std_logic_vector(NCHAN-1 downto 0);         
signal arr_decoder_qrow         : t_arr_slv8;
signal arr_decoder_ccol         : t_arr_slv6;
signal arr_decoder_hitmap       : t_arr_slv16;
signal arr_decoder_tot          : t_arr_slv64;                    -- ToT data packed into MSBs of bus. Lower bits zero
signal arr_decoder_dv           : std_logic_vector(NCHAN-1 downto 0);       

signal arr_decoder_busy         : std_logic_vector(NCHAN-1 downto 0);           
signal arr_decoder_ready        : std_logic_vector(NCHAN-1 downto 0);           
signal arr_decoder_errs         : t_arr_slv3;           
signal any_decoder_errs         : std_logic_vector( 7 downto 0);
signal all_decoder_err          : std_logic;
signal arr_fail_msgs            : std_logic_vector(NCHAN-1 downto 0) := X"00";

-- Bus of decoder busy signals
signal decoders_busy            : std_logic_vector( 7 downto 0);    -- Set by each decoder when running. 

-- Checker outputs
signal arr_checker_status       : t_arr_slv8;
signal arr_checker_err_dv       : std_logic_vector(NCHAN-1 downto 0);           
signal checker0_errs            : std_logic_vector( 7 downto 0);           
signal arr_checker_err_count    : t_arr_slv8;           
signal arr_checker_ready_out    : std_logic_vector(NCHAN-1 downto 0);           
signal any_checker_errs         : std_logic_vector( 7 downto 0);
signal all_checker_err          : std_logic;
signal arr_tied_high            : std_logic_vector(NCHAN-1 downto 0);

-- Blinker and pulse stretcher signals
constant N_PULSE                : integer := 6;
signal led_blink                : std_logic;
signal tick_sec                 : std_logic;   -- tick every 1 sec
signal arr_pulse                : std_logic_vector(N_PULSE-1 downto 0);
signal arr_pulse_stretched      : std_logic_vector(N_PULSE-1 downto 0);

signal fail_msg0                : std_logic := '0';
signal fail_msg1                : std_logic := '0';

attribute mark_debug                        : string;
attribute keep                              : string;
-- Outputs of unencoded data from hitmaker 
attribute mark_debug of exp_hit_dv          : signal is "true";  -- output   expected data valid
attribute mark_debug of exp_hit_eos         : signal is "true";  -- output             
attribute mark_debug of exp_hit_eoe         : signal is "true";  -- output            
attribute mark_debug of exp_hit_qrow        : signal is "true";  -- output   [ 7:0]   
attribute mark_debug of exp_hit_ccol        : signal is "true";  -- output   [ 5:0]   
attribute mark_debug of exp_hit_hitmap      : signal is "true";  -- output   [15:0]   
attribute mark_debug of exp_hit_tot         : signal is "true";  -- output   [64:0]   
attribute mark_debug of exp_hit_tot_size    : signal is "true";  -- output   [6:0]   
attribute mark_debug of exp_hit_tot_dv      : signal is "true";  -- output   expected tot data valid
attribute mark_debug of exp_hit_tot_eos     : signal is "true";  -- output   expected tot eos

-- Output from hit_checker {err_eoe, err_eos, err_tot, err_hitmap, err_ccol, err_qrow, err_tag, err_chip_id};
attribute mark_debug of checker0_errs       : signal is "true";  -- 

begin
    
    brd_switches    <= GPIO_DIP_SW3 & GPIO_DIP_SW2 & GPIO_DIP_SW1 & GPIO_DIP_SW0;
    brd_reset_in    <= CPU_RESET;   


    -------------------------------------------------------------
    -- Wrapper for clock MCMM reset logic
    -------------------------------------------------------------
    u_clkreset : entity work.clkreset
    port map(
        reset_in                => brd_reset_in             ,  -- input
        clk_in1_p               => SYSCLK_P                 ,  -- input 
        clk_in1_n               => SYSCLK_N                 ,  -- input

        clk                     => clk                      ,  -- output
        lock                    => clkreset_lock            ,  -- output
        reset                   => reset                       -- output
    );

    --------------------------------------
    -- Debounce start
    --------------------------------------
    u_debounce_start : entity work.debounce            
    port map(
        clk                     => clk        ,  
        reset                   => reset      ,
        sw_in                   => GPIO_SW_S  ,  -- input
        sw_out                  => btn_start     -- output
    );

    u_debounce_stop : entity work.debounce            
    port map(
        clk                     => clk        ,  
        reset                   => reset      ,
        sw_in                   => GPIO_SW_N  ,  -- input
        sw_out                  => btn_stop      -- output
    );

    
    --------------------------------------
    -- Debounce DIP switches and set hits per stream. Hits per stream = 2**([switch input] + 1)) - 1
    --------------------------------------
    u_set_stream_size : entity work.set_stream_size
    port map(
        clk                    => clk                ,
        reset                  => reset              ,   
        switches               => brd_switches       ,  -- [ 3:0] input
        stream_size            => reg_words_per_stream  -- [15:0] output for test_encode_decode
    );
    reg_hits_per_stream     <= X"FFFF";  -- Set to max so that 'reg_words_per_stream' is the controlling parameter



    -------------------------------------------------------------
    -- Use debounced buttons to start and stop hitmaker
    -------------------------------------------------------------
    pr_ctrl : process (reset, clk)
    begin
        if (reset = '1') then
            hitmaker_start  <= '0';
            hitmaker_enable <= '0';

        elsif rising_edge(clk) then

            if (btn_start = '1') then
                hitmaker_start  <= '1';
                hitmaker_enable <= '1';
            elsif (btn_stop = '1') then
                hitmaker_enable <= '0';
                hitmaker_start  <= '0';
            end if;

        end if;
    end process;


    -------------------------------------------------------------
    -- Generate hit data and convert into 64-bit Aurora packets
    -------------------------------------------------------------
    u_hitmaker : entity work.hitmaker
    port map(
        clk                     => clk                      , -- input            
        reset                   => reset                    , -- input            

        enable                  => hitmaker_enable          , -- input             Allow stream generation
        start                   => hitmaker_start           , -- input             Begin stream generation
        ready_out               => hitmaker_ready           , -- output            Normally high. Goes low when any internal FIFO is over-threshold
        busy                    => hitmaker_busy            , -- output            Set low when din_dv=1 then high after last dout of an event   

        -- Control parameters
        reg_mode_evgen          => reg_mode_evgen           , -- input    [ 1:0]   Type of data 00 = incrementing hitmap, 01 = 3x3 clusters, 10 cluster + vertical line, 11 cluster+vert+horiz lines
        reg_seed                => reg_seed                 , -- input    [31:0]   Seed to initialize the pseudo-random number generator
        reg_hits_per_stream     => reg_hits_per_stream      , -- input    [15:0]  
        reg_words_per_stream    => reg_words_per_stream     , -- input    [15:0]  
        reg_lv_density          => reg_lv_density           , -- input    [ 4:0]   Parameter to set the probability of a vertical line of hits occurring. Can be zero
        reg_lv_maxlen           => reg_lv_maxlen            , -- input    [ 4:0]   Parameter to set the max length of a v-line of hits occurring
        reg_cl_density          => reg_cl_density           , -- input    [11:0]   Parameter to set the range of the increment in x,y from one cluster to the next.
        reg_cl_max              => reg_cl_max               , -- input    [11:0]   Parameter to set the max number of clusters+lines to generate.
        reg_restart             => reg_restart              , -- input             

        reg_en_encode           => reg_en_encode            , -- input             '1' = Encode (Compress) din. '0' = dout is din, dout_size = 16 (5'b1000)
        reg_en_tot              => reg_en_tot               , -- input             '1' = ToT enabled, '0'= No ToT data
        reg_mode_tot            => reg_mode_tot             , -- input             '0' = Constant (tot_value), '1' = Incrementing
        reg_tot_value           => reg_tot_value            , -- input    [ 3:0]   ToT value for constant mode
        reg_tag_init            => reg_tag_init             , -- input    [ 7:0]   Tag to start output stream. Subsequent tags (internal) will be 11-bit
        reg_chip_id             => reg_chip_id              , -- input    [ 1:0]    
        reg_en_chip_id          => reg_en_chip_id           , -- input             Enable chip ID[1:0]
        reg_en_eos              => reg_en_eos               , -- input             Enable min 6 zeros output to mark end of stream

        -- Output of raw event generator data, for comparison with resulting data after encoding then decoding 
        hit_dv                  => exp_hit_dv               , -- output   expected data valid
        hit_eos                 => exp_hit_eos              , -- output             
        hit_eoe                 => exp_hit_eoe              , -- output            
        hit_qrow                => exp_hit_qrow             , -- output   [ 7:0]   
        hit_ccol                => exp_hit_ccol             , -- output   [ 5:0]   
        hit_hitmap              => exp_hit_hitmap           , -- output   [15:0]   

        hit_tot                 => exp_hit_tot              , -- output   [64:0]   
        hit_tot_size            => exp_hit_tot_size         , -- output   [6:0]   
        hit_tot_dv              => exp_hit_tot_dv           , -- output   expected tot data valid 
        hit_tot_eos             => exp_hit_tot_eos          , -- output   expected tot eos

        -- Output of encoded data
        ready_in                => hitmaker_ready_in        , -- input              Normally high from downstream sinks. Goes low when sink cannot accept data
        dout                    => hitmaker_dout            , -- output  [ 62:0]     
        dout_eos                => hitmaker_dout_eos        , -- output             Set for end-of-stream. Last hit in stream          
        dout_eoe                => hitmaker_dout_eoe        , -- output             Set for end-of-event. Last hit in event           
        dout_ns                 => hitmaker_dout_ns         , -- output             New stream bit (Bit 63 of data)          
        dout_dv                 => hitmaker_dout_dv           -- output             Set when new dout produced            
    );
    --hitmaker_ready_in           <= '1'; -- decoder_ready and checker_ready_out;
    hitmaker_ready_in           <= arr_decoder_ready(0) and arr_checker_ready_out(0);

    exp_hitmap_reversed(0)      <= exp_hit_hitmap(15);
    exp_hitmap_reversed(1)      <= exp_hit_hitmap(14);
    exp_hitmap_reversed(2)      <= exp_hit_hitmap(13);
    exp_hitmap_reversed(3)      <= exp_hit_hitmap(12);
    exp_hitmap_reversed(4)      <= exp_hit_hitmap(11);
    exp_hitmap_reversed(5)      <= exp_hit_hitmap(10);
    exp_hitmap_reversed(6)      <= exp_hit_hitmap(9);
    exp_hitmap_reversed(7)      <= exp_hit_hitmap(8);
    exp_hitmap_reversed(8)      <= exp_hit_hitmap(7);
    exp_hitmap_reversed(9)      <= exp_hit_hitmap(6);
    exp_hitmap_reversed(10)     <= exp_hit_hitmap(5);
    exp_hitmap_reversed(11)     <= exp_hit_hitmap(4);
    exp_hitmap_reversed(12)     <= exp_hit_hitmap(3);
    exp_hitmap_reversed(13)     <= exp_hit_hitmap(2);
    exp_hitmap_reversed(14)     <= exp_hit_hitmap(1);
    exp_hitmap_reversed(15)     <= exp_hit_hitmap(0);

    -------------------------------------------------------------
    -- Stream distributor
    -------------------------------------------------------------
    u_distrib_stream : entity work.distrib_stream
    port map (
        reset                   => reset                    , -- in    std_logic;
        clk                     => clk                      , -- in    std_logic;

        busy                    => dist_strm_busy           , -- out   std_logic;                      -- Status. Set once a 'NS=1' is seen. Cleared when all decoders are not busy

        -- Decoder channel updated is sent to distrib_exp  
        stream_chan             => dist_strm_chan           , -- out   std_logic_vector( 2 downto 0);  -- Encoded data channel number (0-7)
        stream_chan_dv          => dist_strm_chan_dv        , -- out   std_logic;                      -- New stream channel data valid
        stream_drop             => dist_strm_drop           , -- out   std_logic;                      -- Dropping current stream

        -- Encoded stream data input from hit generator
        din                     => hitmaker_dout            , -- in    std_logic_vector(62 downto 0);  -- Input encoded stream data
        din_ns                  => hitmaker_dout_ns         , -- in    std_logic;                      -- NS (new_stream) bit
        din_dv                  => hitmaker_dout_dv         , -- in    std_logic;                      -- Data valid

        -- Stream outputs to decoders. Only one channel is active at a time
        dout                    => dist_strm_dout           , -- out   std_logic_vector(62 downto 0);  -- Input encoded stream data
        dout_ns                 => dist_strm_dout_ns        , -- out   std_logic;                      -- NS (new_stream) bit
        dout_chan               => dist_strm_dout_chan      , -- out   std_logic_vector( 2 downto 0);  -- Encoded data channel number (0-7)
        dout_dvs                => dist_strm_dout_dvs       , -- out   std_logic_vector( 7 downto 0);  -- Data valids
        decoders_busy           => decoders_busy              -- in    std_logic_vector( 7 downto 0)   -- Set by each decoder when running. 
    );
    
    -------------------------------------------------------------
    -- Expected data distributor. Routes original data to 
    -- hit_checkers for verification of correct decoding
    -------------------------------------------------------------
    u_distrib_exp : entity work.distrib_exp
    port map (
        reset                   => reset                    , -- in    std_logic;
        clk                     => clk                      , -- in    std_logic;

        busy                    => dist_exp_busy            , -- out   std_logic;                      -- Status. Set once a 'NS=1' is seen. Cleared when all decoders are not busy
        status                  => dist_exp_status          , -- out   std_logic_vector( 7 downto 0);  -- Status. FIFO overflow

        -- Decoder channel selected by 'distrib_stream' block 
        stream_chan             => dist_strm_chan           , -- in    std_logic_vector( 2 downto 0);  -- Encoded data channel number (0-7)
        stream_chan_dv          => dist_strm_chan_dv        , -- in    std_logic;                      -- Data valid
        stream_drop             => dist_strm_drop           , -- in    std_logic;                      -- iDistrib_stream is dropping current stream

        -- Un-encoded event generator data from hit generator, for comparison with data after decoding 
        hit_eos                 => exp_hit_eos              , -- in    std_logic;  
        hit_eoe                 => exp_hit_eoe              , -- in    std_logic; 
        hit_qrow                => exp_hit_qrow             , -- in    std_logic_vector( 7 downto 0); 
        hit_ccol                => exp_hit_ccol             , -- in    std_logic_vector( 5 downto 0); 
        hit_hitmap              => exp_hitmap_reversed      , -- in    std_logic_vector(15 downto 0); 
        hit_dv                  => exp_hit_dv               , -- in    std_logic;                      -- Expected data valid

        hit_tot                 => exp_hit_tot              , -- in    std_logic_vector(63 downto 0);  -- ToT data packed into MSBs of bus
        hit_tot_size            => exp_hit_tot_size         , -- in    std_logic_vector( 6 downto 0);
        hit_tot_dv              => exp_hit_tot_dv           , -- in    std_logic;                      -- Expected ToT data valid. ToT data is delayed from other expected data.

        -- Un-encoded event generator data to hit_checkers for comparison with data after decoding 
        exp_eos                 => dist_exp_eos             , -- out   std_logic;  
        exp_eoe                 => dist_exp_eoe             , -- out   std_logic; 
        exp_qrow                => dist_exp_qrow            , -- out   std_logic_vector( 7 downto 0); 
        exp_ccol                => dist_exp_ccol            , -- out   std_logic_vector( 5 downto 0); 
        exp_hitmap              => dist_exp_hitmap          , -- out   std_logic_vector(15 downto 0); 
        exp_tot                 => dist_exp_tot             , -- out   std_logic_vector(63 downto 0);  -- ToT data packed into MSBs of bus
        exp_tot_size            => dist_exp_tot_size        , -- out   std_logic_vector( 6 downto 0);
        exp_chan                => dist_exp_chan            , -- out   std_logic_vector( 2 downto 0);  -- Encoded data channel number (0-7)
        exp_dvs                 => dist_exp_dvs               -- out   std_logic_vector( 7 downto 0);                      -- Expected data valid
    );

    -- Distributor is set for eight decoders. Set non-existent decoders 'busy'
    arr_tied_high   <= (others=>'1');
    decoders_busy   <= arr_decoder_busy;

 
        -------------------------------------------------------------
        -- Hit decoder to convert 64-bit 'Aurora-formatted' words 
        -- back into uncompressed, separate fields.
        -------------------------------------------------------------
        u_decode : entity work.decode_engine_2
        port map (
            clk                     => clk                      , -- 
            reset                   => reset                    , -- 

            busy                    => arr_decoder_busy(0)      , -- 
            ready                   => arr_decoder_ready(0)     , -- When the engine is ready to recieve raw stream data
            errors                  => arr_decoder_errs(0)      , -- 

            -- Control settings (may, or may not be implemented)
            reg_en_encode           => reg_en_encode            , -- input  '1' = Encode (Compress) din. '0' = dout is din, dout_size = 16 (5'b1000)
            reg_en_tot              => reg_en_tot               , -- input  '1' = ToT enabled, '0'= No ToT data
            reg_en_chip_id          => reg_en_chip_id           , -- input  Enable chip ID[1:0]
            reg_en_eos              => reg_en_eos               , -- input  Enable min 6 zeros output to mark end of stream

            din                     => dist_strm_dout           , -- Raw data from the data stream
            din_ns                  => dist_strm_dout_ns        , -- Set on first word of a new stream
            din_chan                => dist_strm_dout_chan      , -- Encoded data channel number (0-7)
            din_dv                  => dist_strm_dout_dvs(0)    , -- The stream data that is being advertised is valid

            -- Decoded hit data 
            dout_chip_id            => arr_decoder_chip_id(0)   , -- output current chip_id [1:0]            
            dout_tag                => arr_decoder_tag(0)       , -- output current tag     [7:0]  
            dout_eos                => arr_decoder_eos(0)       , -- output end-of-stream            
            dout_eoe                => arr_decoder_eoe(0)       , -- output end-of-event           
            dout_qrow               => arr_decoder_qrow(0)      , -- output qrow    [ 7:0]   
            dout_ccol               => arr_decoder_ccol(0)      , -- output ccol    [ 5:0]   
            dout_hitmap             => arr_decoder_hitmap(0)    , -- output hitmap  [15:0]   
            dout_tot                => arr_decoder_tot(0)       , -- output tot     [63:0] ToT data packed into MSBs of bus
            dout_dv                 => arr_decoder_dv(0)          -- output data valid           
        );


        -------------------------------------------------------------
        -- hit_checker. 
        -- Stores generated hit data in a FIFO. Reads it out and 
        -- compares expected value agains actual decoded value.
        -- Expected ToT is made from tot mode register controls and 
        -- expected hitmap size.
        -------------------------------------------------------------
        -- checker_fail bits
        -------------------------------------------------------------
        -- Bit    Failure type
        --  0        chip_id
        --  1        tag
        --  2        qrow
        --  3        ccol
        --  4        hitmap
        --  5        ToT
        --  6        EOS
        --  7        EOE
        -------------------------------------------------------------
        u_hit_checker : entity work.hit_checker
        port map (
            clk                     => clk                      ,  
            reset                   => reset                    ,  
            restart                 => reg_restart              , 

            -- Register setup. Operating mode
            reg_en_tot              => reg_en_tot               , -- input             '1' = ToT enabled, '0'= No ToT data
            reg_mode_tot            => reg_mode_tot             , -- input             '0' = Constant (tot_value), '1' = Incrementing
            reg_tot_value           => reg_tot_value            , -- input    [ 3:0]   ToT value for constant mode
            reg_tag_init            => reg_tag_init             , -- input    [ 7:0]   Tag to start output stream. Subsequent tags (internal) will be 11-bit
            reg_chip_id             => reg_chip_id              , -- input    [ 1:0]    
            reg_en_chip_id          => reg_en_chip_id           , -- input             Enable chip ID[1:0]
            reg_en_eos              => reg_en_eos               , -- input             Enable min 6 zeros output to mark end of stream

            status                  => arr_checker_status(0)    , -- TBD status bits [7:0]

            -- Expected data from hitmaker through distrib_exp
            exp_eos                 => dist_exp_eos             , -- input             
            exp_eoe                 => dist_exp_eoe             , -- input            
            exp_qrow                => dist_exp_qrow            , -- input   [ 7:0]   
            exp_ccol                => dist_exp_ccol            , -- input   [ 5:0]   
            exp_hitmap              => dist_exp_hitmap          , -- input   [15:0]   
            exp_dv                  => dist_exp_dvs(0)          , -- input   expected data valid

            exp_tot                 => dist_exp_tot             , -- input   [15:0]   
            exp_tot_size            => dist_exp_tot_size        , -- input    [6:0]   
            exp_tot_dv              => dist_exp_dvs(0)          , -- input   expected data valid

            -- Actual data from decoder 
            act_chip_id             => arr_decoder_chip_id(0)   , -- input current chip_id [ 1:0]           
            act_tag                 => arr_decoder_tag(0)       , -- input current tag     [ 7:0]      
            act_eos                 => arr_decoder_eos(0)       , -- input end-of-stream            
            act_eoe                 => arr_decoder_eoe(0)       , -- input end-of-event    Used to check incrementing tag
            act_qrow                => arr_decoder_qrow(0)      , -- input qrow    [ 7:0]   
            act_ccol                => arr_decoder_ccol(0)      , -- input ccol    [ 5:0]   
            act_hitmap              => arr_decoder_hitmap(0)    , -- input hitmap  [15:0]   
            act_tot                 => arr_decoder_tot(0)       , -- input tot     [63:0] ToT data packed into MSBs of bus
            act_dv                  => arr_decoder_dv(0)        , -- input data valid           

            dout_err_dv             => arr_checker_err_dv(0)    , -- output result valid
            dout_errs               => checker0_errs            , -- output fail bus [7:0]
            dout_err_count          => arr_checker_err_count(0) , -- output result error count [7:0]
            ready_out               => arr_checker_ready_out(0)   -- output ready for a new stream
        );
    --                             7      6        5         4          3         2         1         0
    -- checker dout_errs   = {err_eoe, err_eos, err_tot, err_hitmap, err_ccol, err_qrow, err_tag, err_chip_id};

    arr_checker_err_dv(7 downto 1)      <= (others=>'0');            -- output result valid
    arr_checker_err_count(1 to 7)       <= (others=>(others=>'0'));  -- output result error count [7:0]
    arr_checker_ready_out(7 downto 1)   <= (others=>'0');            -- output ready for a new stream
    dist_strm_dout_dvs(7 downto 1)      <= (others=>'0');            -- The stream data that is being advertised is valid
    arr_decoder_busy(7 downto 1)        <= (others=>'0'); -- 
    arr_decoder_ready(7 downto 1)       <= (others=>'0'); -- When the engine is ready to recieve raw stream data
    arr_decoder_errs(1 to 7)            <= (others=>(others=>'0')); -- 

    -------------------------------------------------------------
    -- Main 
    -------------------------------------------------------------
    -- Register setup
    reg_seed                <= X"FFFFFFFF"  ; -- [31:0]   Seed to initialize the pseudo-random number generator
    reg_mode_evgen          <= "00"         ; -- [ 1:0]   Type of data 00 = incrementing hitmap, 01 = 3x3 clusters, 10 cluster + vertical line, 11 cluster+vert+horiz lines
    reg_lv_density          <= "00100"      ; -- [ 4:0]   Parameter to set the probability of a vertical line of hits occurring. Can be zero
    reg_lv_maxlen           <= "00100"      ; -- [ 4:0]   Parameter to set the max length of a v-line of hits occurring
    reg_cl_density          <= X"006"       ; -- [11:0]   Parameter to set the range of the increment in x,y from one cluster to the next.
    reg_cl_max              <= X"010"       ; -- [11:0]   Parameter to set the max number of clusters+lines to generate.
    reg_restart             <= '0'          ; --          
    reg_en_encode           <= '1'          ; --          '1' = Encode (Compress) din. '0' = dout is din, dout_size = 16 (5'b1000)
    reg_en_tot              <= '1'          ; --          '1' = ToT enabled, '0'= No ToT data
    reg_mode_tot            <= '0'          ; --          '0' = Constant (tot_value), '1' = Incrementing
    reg_tot_value           <= X"3"         ; -- [ 3:0]   ToT value for constant mode
    reg_tag_init            <= X"05"        ; -- [ 7:0]   Tag to start output stream. Subsequent tags (internal) will be 11-bit
    reg_chip_id             <= "01"         ; -- [ 1:0]    
    reg_en_chip_id          <= '1'          ; --          Enable chip ID[1:0]
    reg_en_eos              <= '1'          ; --          Enable min 6 zeros output to mark end of stream


    ------------------------------------------------------------------------------
    -- Random data used to set reg_hits_per_stream
    ------------------------------------------------------------------------------
    --u_simplePRNG : entity work.simplePRNG 
    --port map(
    --    clk        => clk           ,  -- input   logic           
    --    reset      => reset         ,  -- input   logic           
    --    restart    => '0'           ,  -- input   logic           
    --    seed       => random_seed   ,  -- input   logic   [31:0]  
    --    step       => '1'           ,  -- input   logic           
    --    dout       => random_dout   ,  -- output  logic   [31:0]  
    --    new_data   => open             -- output  reg             
    --);
    random_seed <= X"55555555";


    --------------------------------------
    -- Blinky and pulse stretcher
    --------------------------------------
    u_blink : entity work.blink 
    generic map(
        G_NBITS                 => N_PULSE,
        G_INTERVAL_TICK_SLOW    => 20
    )
    port map(
        reset       => reset                ,  -- input
        clk         => clk                  ,  -- input

        flash       => led_blink            ,  -- output  
        tick_sec    => tick_sec             ,  -- output
        tick_msec   => open                 ,  -- output
        tick_usec   => open                 ,  -- output

        pulse       => arr_pulse            ,  -- [G_NBITS-1:0] input 
        stretched   => arr_pulse_stretched     -- [G_NBITS-1:0] output
    );

    -----------------------------------------------------------------------------------
    -- Register debug signals
    -----------------------------------------------------------------------------------
    pr_leds_debug : process (reset, clk)
    begin
        if (reset = '1') then
            arr_pulse               <= (others=>'0');
            any_checker_errs        <= (others=>'0');
            all_checker_err         <= '0'; 
            
            any_decoder_errs        <= (others=>'0');
            all_decoder_err         <= '0'; 
            
        elsif rising_edge(clk) then

            arr_pulse(0)            <= dist_strm_drop;
            arr_pulse(1)            <= checker0_errs(2);  -- err_qrow
            arr_pulse(2)            <= checker0_errs(3);  -- err_ccol
            arr_pulse(3)            <= checker0_errs(4);  -- err_hitmap
            arr_pulse(4)            <= checker0_errs(5);  -- err_tot
            arr_pulse(5)            <= checker0_errs(6);  -- err_eos

            -- Set a bit in 'any_checker_errs' for any error in each checker
            --any_checker_errs(0)     <= ;


            -- Set if any checker has any error
            all_checker_err         <= or_reduce(checker0_errs);

            -- Set a bit in 'any_decoder_errs' for any error in each decoder
            any_decoder_errs(0)     <= or_reduce(arr_decoder_errs(0));
            any_decoder_errs(1)     <= or_reduce(arr_decoder_errs(1));
            any_decoder_errs(2)     <= or_reduce(arr_decoder_errs(2));
            any_decoder_errs(3)     <= or_reduce(arr_decoder_errs(3));
            any_decoder_errs(4)     <= or_reduce(arr_decoder_errs(4));
            any_decoder_errs(5)     <= or_reduce(arr_decoder_errs(5));
            any_decoder_errs(6)     <= or_reduce(arr_decoder_errs(6));
            any_decoder_errs(7)     <= or_reduce(arr_decoder_errs(7));

            -- Set if any decoder has any error
            all_decoder_err         <= or_reduce(any_decoder_errs);

            GPIO_LED_0_LS           <= led_blink;
            GPIO_LED_1_LS           <= hitmaker_busy;
            GPIO_LED_2_LS           <= arr_pulse_stretched(0);  -- dist_strm_drop

            GPIO_LED_3_LS           <= arr_pulse_stretched(1);  -- err_qrow 
            GPIO_LED_4_LS           <= arr_pulse_stretched(2);  -- err_ccol 
            GPIO_LED_5_LS           <= arr_pulse_stretched(3);  -- err_hitmap 
            GPIO_LED_6_LS           <= arr_pulse_stretched(4);  -- err_tot 
            GPIO_LED_7_LS           <= arr_pulse_stretched(5);  -- err_eos 

            DEBUG_OUT(0)            <= dist_strm_drop;
            DEBUG_OUT(1)            <= checker0_errs(2);  -- err_qrow;
            DEBUG_OUT(2)            <= checker0_errs(3);  -- err_ccol;
            DEBUG_OUT(3)            <= checker0_errs(4);  -- err_hitmap;
            DEBUG_OUT(4)            <= checker0_errs(5);  -- err_tot;  
            DEBUG_OUT(5)            <= checker0_errs(6);  -- err_eos;  
            DEBUG_OUT(6)            <= arr_decoder_dv(0);
          --DEBUG_OUT(7)            <= any_checker_errs(5);
          --DEBUG_OUT(8)            <= any_checker_errs(6);
          --DEBUG_OUT(9)            <= any_checker_errs(7);

        end if;

    end process;

    fail_msg0           <= '1' when (all_checker_err /= '0') and (reset = '0') else '0';
    assert (fail_msg0 = '0') report "all_checker_err" severity FAILURE;

    fail_msg1           <= '1' when (all_decoder_err /= '0') and (reset = '0') else '0';
    assert (fail_msg1 = '0') report "all_decoder_err" severity FAILURE;
               

end struct_x1;

