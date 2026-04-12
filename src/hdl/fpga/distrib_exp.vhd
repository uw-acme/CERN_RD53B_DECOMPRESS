-------------------------------------------------------------------------------
-- File       : distrib_exp.vhd
-------------------------------------------------------------------------------
-- [Filename]       distrib_exp.vhd [RTL]
-- [Project]        Stream Decoder for RD53B data in an FPGA
-- [Author]         
-- [Language]       VHDL
-- [Created]        
-- [Description]    Distribute expected decode data to eight instances of the hit_checker
--                  Uses the channel assigned by the distrib_stream block for its output.
--                  If the distrib_stream drops a stream then this block will drop the 
--                  same expected data stream. Since the expected data input to this block
--                  is seen a few cycles before the distrib_stream starts receiving the
--                  corresponding encoded stream data, the expected data must be stored until
--                  the channel and drop status has been decided.
-- 
-- 
-- There is no 'end-of-stream' indicator with transmitted encoded data.
-- However this testbench block can use the EOS signal from the hitmaker to buffer
-- the expected data until the 'distrib_stream' block has picked the next decoder.
-------------------------------------------------------------------------------
library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity distrib_exp is
port (
    reset           : in    std_logic;
    clk             : in    std_logic;

    busy            : out   std_logic;                      -- Status. 
    status          : out   std_logic_vector( 7 downto 0);  -- Status. FIFO overflow

    -- Decoder channel selected by 'distrib_stream' block 
    stream_chan     : in    std_logic_vector( 2 downto 0);  -- Encoded data channel number (0-7)
    stream_chan_dv  : in    std_logic;                      -- Data valid
    stream_drop     : in    std_logic;                      -- Distrib_stream is dropping current stream

    -- Un-encoded event generator data from hit generator, for comparison with data after decoding 
    hit_eos         : in    std_logic;  
    hit_eoe         : in    std_logic; 
    hit_qrow        : in    std_logic_vector( 7 downto 0); 
    hit_ccol        : in    std_logic_vector( 5 downto 0); 
    hit_hitmap      : in    std_logic_vector(15 downto 0); 
    hit_dv          : in    std_logic;                      -- Expected data valid

    hit_tot         : in    std_logic_vector(63 downto 0);  -- ToT data packed into MSBs of bus
    hit_tot_size    : in    std_logic_vector( 6 downto 0);
    hit_tot_dv      : in    std_logic;                      -- Expected ToT data valid. ToT data is delayed from other expected data.

    -- Un-encoded event generator data to hit_checkers for comparison with data after decoding 
    exp_eos         : out   std_logic;  
    exp_eoe         : out   std_logic; 
    exp_qrow        : out   std_logic_vector( 7 downto 0); 
    exp_ccol        : out   std_logic_vector( 5 downto 0); 
    exp_hitmap      : out   std_logic_vector(15 downto 0); 
    exp_tot         : out   std_logic_vector(63 downto 0);  -- ToT data packed into MSBs of bus
    exp_tot_size    : out   std_logic_vector( 6 downto 0);
    exp_chan        : out   std_logic_vector( 2 downto 0);  -- Encoded data channel number (0-7)
    exp_dvs         : out   std_logic_vector( 7 downto 0)   -- Expected data valid
);
end distrib_exp;

architecture rtl of distrib_exp is

-- State machine variable for selecting decode engines
type t_state  is (
    S_IDLE          ,   -- Waiting for data with new stream set
    S_LOOP          ,   -- Output data to current channel. Switch channel if din_ns is set. 
    S_WAIT          ,   -- Delay to allow FIFO 'empty' to update
    S_EOS               -- Wait for stream distributor to update stream channel
);
signal state                : t_state;  
signal sm_rd_fifos          : std_logic; 
signal sm_busy              : std_logic; 
signal sm_dvs               : std_logic_vector( 7 downto 0);  -- One channel data valid active

-- Expected (un-encoded hit data) is written into FIFOs. These are needed 
-- because the encoded data is delayed and the distributor has not chosen a channel when the
-- expected data is received.
-- One FIFO for hit map,addr, and one for ToT data since it is delayed by a few cycles
-- Both FIFOs can be read simultaneously to align the two types of data for the hit_checker blocks

-- Expected hit data FIFO I/O signals
signal fhit_wr              : std_logic; 
signal fhit_rd              : std_logic; 
signal fhit_din             : std_logic_vector(31 downto 0);
signal fhit_dout            : std_logic_vector(31 downto 0);
signal fhit_uflow           : std_logic;
signal fhit_oflow           : std_logic;
signal fhit_full            : std_logic;
signal fhit_empty           : std_logic;
signal fhit_level           : std_logic_vector( 9 downto 0);

-- Expected ToT data FIFO I/O signals
signal ftot_din, ftot_dout  : std_logic_vector(63 downto 0); 
signal ftot_size_din        : std_logic_vector(31 downto 0);     
signal ftot_size_dout       : std_logic_vector(31 downto 0);     
signal ftot0_level          : std_logic_vector( 9 downto 0);
signal ftot1_level          : std_logic_vector( 9 downto 0);
signal ftot_size_level      : std_logic_vector( 9 downto 0);
signal ftot_wr,  ftot_rd    : std_logic;

signal ftot0_full           : std_logic;
signal ftot0_empty          : std_logic;
signal ftot0_uflow          : std_logic;
signal ftot0_oflow          : std_logic;
signal ftot1_full           : std_logic;
signal ftot1_empty          : std_logic;
signal ftot1_uflow          : std_logic;
signal ftot1_oflow          : std_logic;
signal ftot_size_full       : std_logic;
signal ftot_size_empty      : std_logic;
signal ftot_size_uflow      : std_logic;
signal ftot_size_oflow      : std_logic;
    
begin      

    busy    <= sm_busy;


    -----------------------------------------------------------------------------------
    --  Write expected data into FIFOs. 
    --  32 bits of hit data and 64+7 bits of ToT data and ToT size.
    --  TODO: ToT size FIFO can be reduced from 32 bit to 7 or combined with ToT into a 
    --  single 71-bit FIFO.
    --  exp_eos        1-bit
    --  exp_eoe        1-bit
    --  exp_qrow       8-bit
    --  exp_ccol       6-bit
    --  exp_hitmap    16-bit 
    -----------------------------------------------------------------------------------
    pr_fifos_wr : process (reset, clk)
    begin
        if (reset='1') then

            fhit_din        <= (others=>'0');
            fhit_wr         <= '0';
            
            ftot_din        <= (others=>'0');
            ftot_size_din   <= (others=>'0');
            ftot_wr         <= '0';

        elsif rising_edge(clk) then

            fhit_din                    <= hit_eos & hit_eoe & hit_qrow & hit_ccol & hit_hitmap;
            fhit_wr                     <= hit_dv;

            ftot_din                    <= hit_tot;
            ftot_size_din(31 downto 7)  <= (others=>'0');
            ftot_size_din( 6 downto 0)  <= hit_tot_size;
            ftot_wr                     <= hit_tot_dv;

        end if;

    end process;

    -- State machine reads both FIFOs at the same time
    fhit_rd <= sm_rd_fifos;
    ftot_rd <= sm_rd_fifos;


    ------------------------------------------------------------------------------
    -- FIFOs to store expected data until the output channel for the encoded data
    -- has been selected.  Then the same destination is used for this expected data.
    -- Both ToT data is written to the FIFOs a few clock cycles after the unencoded
    -- hit data but all FIFOs can be read at the same time.
    --
    -- NOTE: This uses four 32-bit wide FIFOs to minimize the number of different IP blocks
    --       but the FIFOs should really be 32-bit, 64-bit and 7-bit.
    ------------------------------------------------------------------------------
    u_fifo_hit          : entity work.fifo_chk_512x32b      -- Block RAM 512x32bit
    port map(
        clk             => clk                      ,  -- input  wire 
        srst            => reset                    ,  -- input  wire 
        din             => fhit_din                 ,  -- input  wire [31:0] 
        wr_en           => fhit_wr                  ,  -- input  wire 
        rd_en           => fhit_rd                  ,  -- input  wire
        dout            => fhit_dout                ,  -- output wire [31:0]
        full            => fhit_full                ,  -- output wire
        empty           => fhit_empty               ,  -- output wire
        overflow        => fhit_oflow               ,  -- output wire
        underflow       => fhit_uflow               ,  -- output wire
        data_count      => fhit_level                  -- output wire [9:0]
    );

    -- The two 32-bit ToT FIFOs can be combined into one 64-bit FIFO
    u_fifo_tot0         : entity work.fifo_chk_512x32b      -- Block RAM 512x32bit
    port map(
        clk             => clk                      ,  -- input  wire 
        srst            => reset                    ,  -- input  wire 
        din             => ftot_din(31 downto 0)    ,  -- input  wire [31:0] 
        wr_en           => ftot_wr                  ,  -- input  wire 
        rd_en           => ftot_rd                  ,  -- input  wire
        dout            => ftot_dout(31 downto 0)   ,  -- output wire [31:0]
        full            => ftot0_full               ,  -- output wire
        empty           => ftot0_empty              ,  -- output wire
        overflow        => ftot0_oflow              ,  -- output wire
        underflow       => ftot0_uflow              ,  -- output wire
        data_count      => ftot0_level                 -- output wire [9:0]
    );

    u_fifo_tot1         : entity work.fifo_chk_512x32b      -- Block RAM 512x32bit
    port map(
        clk             => clk                      ,  -- input  wire 
        srst            => reset                    ,  -- input  wire 
        din             => ftot_din(63 downto 32)   ,  -- input  wire [31:0] 
        wr_en           => ftot_wr                  ,  -- input  wire 
        rd_en           => ftot_rd                  ,  -- input  wire
        dout            => ftot_dout(63 downto 32)  ,  -- output wire [31:0]
        full            => ftot1_full               ,  -- output wire
        empty           => ftot1_empty              ,  -- output wire
        overflow        => ftot1_oflow              ,  -- output wire
        underflow       => ftot1_uflow              ,  -- output wire
        data_count      => ftot1_level                 -- output wire [9:0]
    );
     
    -- TODO Make FIFO 7-bit
    u_fifo_tot_size     : entity work.fifo_chk_512x32b      -- Block RAM 512x32bit
    port map(
        clk             => clk                      ,  -- input  wire 
        srst            => reset                    ,  -- input  wire 
        din             => ftot_size_din            ,  -- input  wire [31:0] 
        wr_en           => ftot_wr                  ,  -- input  wire 
        rd_en           => ftot_rd                  ,  -- input  wire
        dout            => ftot_size_dout           ,  -- output wire [31:0]
        full            => ftot_size_full           ,  -- output wire
        empty           => ftot_size_empty          ,  -- output wire
        overflow        => ftot_size_oflow          ,  -- output wire
        underflow       => ftot_size_uflow          ,  -- output wire
        data_count      => ftot_size_level             -- output wire [9:0]
    );
    
    status      <= fhit_full  & fhit_empty  & fhit_oflow  & fhit_uflow     
                 & ftot0_full & ftot0_empty & ftot0_oflow & ftot0_uflow;    


    -----------------------------------------------------------------------------------
    -- State machine to read FIFOs and set the output channel.
    -----------------------------------------------------------------------------------
    pr_sm : process (reset, clk)
    begin
        if (reset='1') then

            state           <= S_IDLE;
            sm_rd_fifos     <= '0';
            sm_busy         <= '0';
            sm_dvs          <= (0 => '1', others=>'0');     -- Internal channel data valids. One always high

            exp_eos         <= '0'; 
            exp_eoe         <= '0';
            exp_qrow        <= (others=>'0'); 
            exp_ccol        <= (others=>'0'); 
            exp_hitmap      <= (others=>'0'); 
            exp_tot         <= (others=>'0');
            exp_tot_size    <= (others=>'0');
            exp_chan        <= (others=>'0');   -- Initial channel
            exp_dvs         <= (others=>'0');


        elsif rising_edge(clk) then

            case state is

                ------------------------------------------------
                -- Wait until distrib_stream has selected a channel
                -- Capture channel and set sm_dvs
                ------------------------------------------------
                when S_IDLE   =>
                     
                    if (stream_chan_dv = '1' and stream_drop = '0') then    -- Set one of the sm_dvs bits

                        exp_chan    <= stream_chan;
                        case stream_chan is
                            when "000"  =>  sm_dvs   <= "00000001";
                            when "001"  =>  sm_dvs   <= "00000010";
                            when "010"  =>  sm_dvs   <= "00000100";
                            when "011"  =>  sm_dvs   <= "00001000";
                            when "100"  =>  sm_dvs   <= "00010000";
                            when "101"  =>  sm_dvs   <= "00100000";
                            when "110"  =>  sm_dvs   <= "01000000";
                            when others =>  sm_dvs   <= "10000000";
                        end case;
                        sm_busy         <= '1';
                        state           <= S_WAIT;

                    elsif (stream_chan_dv = '1' and stream_drop = '1') then -- No sm_dvs is set. Other operation is the same
                        exp_chan        <= (others=>'0');
                        sm_dvs          <= (others=>'0');
                        sm_busy         <= '1';
                        state           <= S_WAIT;
                    else
                        exp_chan        <= (others=>'0');
                        sm_dvs          <= (others=>'0');
                        sm_busy         <= '0';
                    end if;

                    -- Output 
--                    if ((fhit_empty = '0') and (ftot0_empty = '0') and (stream_chan_dv = '1') and (stream_drop='0') then 
--
--                        -- Extract fields from expected-data-FIFO
--                        exp_eos         <= fhit_dout(31);               --        
--                        exp_eoe         <= fhit_dout(30);               --       
--                        exp_qrow        <= fhit_dout(29 downto 22);     -- [ 7:0] 
--                        exp_ccol        <= fhit_dout(21 downto 16);     -- [ 5:0] 
--                        exp_hitmap      <= fhit_dout(15 downto  0);     -- [15:0] 
--                        exp_tot         <= ftot_dout;
--                        exp_tot_size    <= ftot_size_dout( 6 downto 0);
--                        exp_dvs         <= sm_dvs;
--                        
--                        sm_rd_fifos     <= '1';
--                        sm_busy         <= '1';
--                        state           <= S_WAIT;
--
--                    else
                        
                        exp_eos         <= '0'; 
                        exp_eoe         <= '0';
                        exp_qrow        <= (others=>'0'); 
                        exp_ccol        <= (others=>'0'); 
                        exp_hitmap      <= (others=>'0'); 
                        exp_tot         <= (others=>'0');
                        exp_tot_size    <= (others=>'0');
                        exp_dvs         <= (others=>'0');

                        sm_rd_fifos     <= '0';
                        sm_busy         <= '0';

                    --end if;


                ------------------------------------------------
                -- Wait for FIFO empty flags to update
                ------------------------------------------------
                when S_WAIT  =>

                    exp_eos         <= '0'; 
                    exp_eoe         <= '0';
                    exp_qrow        <= (others=>'0'); 
                    exp_ccol        <= (others=>'0'); 
                    exp_hitmap      <= (others=>'0'); 
                    exp_tot         <= (others=>'0');
                    exp_tot_size    <= (others=>'0');
                    exp_dvs         <= (others=>'0');

                    sm_rd_fifos     <= '0';
                    state           <= S_LOOP;


                ------------------------------------------------
                -- Output data. Exit loop when EOS is seen
                ------------------------------------------------
                when S_LOOP  =>

                    if ((fhit_empty = '0') and (ftot0_empty = '0')) then 

                        -- Extract fields from expected-data-FIFO
                        exp_eos         <= fhit_dout(31);               --        
                        exp_eoe         <= fhit_dout(30);               --       
                        exp_qrow        <= fhit_dout(29 downto 22);     -- [ 7:0] 
                        exp_ccol        <= fhit_dout(21 downto 16);     -- [ 5:0] 
                        exp_hitmap      <= fhit_dout(15 downto  0);     -- [15:0] 
                        exp_tot         <= ftot_dout;
                        exp_tot_size    <= ftot_size_dout( 6 downto 0);
                        exp_dvs         <= sm_dvs;
                        
                        sm_rd_fifos     <= '1';

                        if (fhit_dout(31) = '1') then   -- End-of-stream
                            state       <= S_IDLE;
                        else        
                            state       <= S_WAIT;
                        end if;

                    else
                        
                        exp_eos         <= '0'; 
                        exp_eoe         <= '0';
                        exp_qrow        <= (others=>'0'); 
                        exp_ccol        <= (others=>'0'); 
                        exp_hitmap      <= (others=>'0'); 
                        exp_tot         <= (others=>'0');
                        exp_tot_size    <= (others=>'0');
                        exp_dvs         <= (others=>'0');
                        sm_rd_fifos     <= '0';

                    end if;


                ------------------------------------------------
                -- A stream has ended. Wait for stream distrib
                -- to update the channel
                ------------------------------------------------
                --when S_EOS  =>
                --
                --    if (stream_chan_dv = '1' and stream_drop = '0') then
                --
                --        exp_chan    <= stream_chan;
                --        case stream_chan is
                --            when "000"  =>  sm_dvs   <= "00000001";
                --            when "001"  =>  sm_dvs   <= "00000010";
                --            when "010"  =>  sm_dvs   <= "00000100";
                --            when "011"  =>  sm_dvs   <= "00001000";
                --            when "100"  =>  sm_dvs   <= "00010000";
                --            when "101"  =>  sm_dvs   <= "00100000";
                --            when "110"  =>  sm_dvs   <= "01000000";
                --            when others =>  sm_dvs   <= "10000000";
                --        end case;
                --        state       <= S_IDLE;      -- Get ready to output next stream
                --
                --    elsif (stream_chan_dv = '1' and stream_drop = '1') then
                --        exp_chan        <= (others=>'0');
                --        sm_dvs          <= (others=>'0');
                --    else
                --        exp_chan        <= (others=>'0');
                --        sm_dvs          <= (others=>'0');
                --    end if;
                --
                --    exp_eos         <= '0'; 
                --    exp_eoe         <= '0';
                --    exp_qrow        <= (others=>'0'); 
                --    exp_ccol        <= (others=>'0'); 
                --    exp_hitmap      <= (others=>'0'); 
                --    exp_tot         <= (others=>'0');
                --    exp_tot_size    <= (others=>'0');
                --
                --    sm_rd_fifos     <= '0';
                --

                ------------------------------------------------
                when others =>
                    state   <= S_IDLE;

            end case;

        end if;

    end process;

end rtl;

