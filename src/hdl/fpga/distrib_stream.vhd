-------------------------------------------------------------------------------
-- File       : distrib_stream.vhd
-------------------------------------------------------------------------------
-- [Filename]       distrib_stream.vhd [RTL]
-- [Project]        Stream Decoder for RD53B data in an FPGA
-- [Author]         
-- [Language]       VHDL
-- [Created]        
-- [Description]    Distribute a series of streams to eight different instances of the decoder
-- 
-- 
-- Input is over a 63-bit bus with a 'ns' (new stream) bit
-- There is no 'end-of-stream' indicator with transmitted encoded data. The
-- 'eos' bit from the hit generator is not available in a real system. EOS can only
-- be detected by seeing 6 or more 'orphan' bits (zeros) in the decoded data or by
-- using the din_ns=1 on the first word of the following stream.
-------------------------------------------------------------------------------
library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity distrib_stream is
port (
    reset           : in    std_logic;
    clk             : in    std_logic;

    busy            : out   std_logic;                      -- Status. Set once a 'NS=1' is seen. Cleared when all decoders are not busy
                                                            
    -- Decoder channel updated  
    stream_chan     : out   std_logic_vector( 2 downto 0);  -- Encoded data channel number (0-7)
    stream_chan_dv  : out   std_logic;                      -- New stream channel data valid
    stream_drop     : out   std_logic;                      -- Set during stream recieve if there is no decoder available. For distrib_exp

    -- Encoded stream data input from hit generator
    din             : in    std_logic_vector(62 downto 0);  -- Input encoded stream data
    din_ns          : in    std_logic;                      -- NS (new_stream) bit
    din_dv          : in    std_logic;                      -- Data valid

    -- Stream outputs to decoders. Only one channel is active at a time
    dout            : out   std_logic_vector(62 downto 0);  -- Input encoded stream data
    dout_ns         : out   std_logic;                      -- NS (new_stream) bit
    dout_chan       : out   std_logic_vector( 2 downto 0);  -- Encoded data channel number (0-7)
    dout_dvs        : out   std_logic_vector( 7 downto 0);  -- Data valid for each decoder channel
    decoders_busy   : in    std_logic_vector( 7 downto 0)   -- Set by each decoder when running. 
);
end distrib_stream;

architecture rtl of distrib_stream is

-- State machine variable for selecting decode engines
type t_state  is (
    S_IDLE          ,   -- Waiting for data with new stream set
    S_RUN               -- Output data stream to current channel. Switch channel if din_ns is set. 
);
signal state                : t_state;  
signal sm_chan              : std_logic_vector( 2 downto 0); 
signal sm_dvs               : std_logic_vector( 7 downto 0); 

signal din_d1               : std_logic_vector(62 downto 0);  -- Input encoded stream data
signal din_ns_d1            : std_logic;                      -- NS (new_stream) bit
signal din_dv_d1            : std_logic;                      -- Data valid

begin      

    stream_chan     <= sm_chan;     -- Encoded data channel number (0-7)

    -----------------------------------------------------------------------------------
    -- State machine to send data to selected decoder.
    -- Initial decoder is channel 0
    -- Maintain channel until a new din_ns=1 is seen then switch the stream to the 
    -- lowest available channel
    -----------------------------------------------------------------------------------
    pr_sm : process (reset, clk)
    begin
        if (reset='1') then

            state           <= S_IDLE;
            busy            <= '0';
            sm_chan         <= (others=>'0');               -- Start with chan = 0
            sm_dvs          <= (0 => '1', others=>'0');
            stream_chan_dv  <= '0'; 
            stream_drop     <= '0'; 

            din_d1          <= (others=>'0');
            din_ns_d1       <= '0'; 
            din_dv_d1       <= '0';

        elsif rising_edge(clk) then

            case state is

                ------------------------------------------------
                -- Wait for initial NS, or NS after an error.
                -- Set 'busy' on first 'ns'. Clear 'busy' when all
                -- decoders are not busy.
                ------------------------------------------------
                when S_IDLE   =>
                
                   if ((din_dv = '1') and (din_ns = '1')) then 

                        state           <= S_RUN;
                        busy            <= '1';
                        din_d1          <= din;
                        din_ns_d1       <= '1'; 
                        din_dv_d1       <= '1';
                        stream_chan_dv  <= '1'; 

                        if    (decoders_busy(0) = '0') then
                            sm_chan         <= "000";
                            sm_dvs          <= "00000001";
                            stream_drop     <= '0'; 
                        elsif (decoders_busy(1) = '0') then
                            sm_chan         <= "001";
                            sm_dvs          <= "00000010";
                            stream_drop     <= '0'; 
                        elsif (decoders_busy(2) = '0') then
                            sm_chan         <= "010";
                            sm_dvs          <= "00000100";
                            stream_drop     <= '0'; 
                        elsif (decoders_busy(3) = '0') then
                            sm_chan         <= "011";
                            sm_dvs          <= "00001000";
                            stream_drop     <= '0'; 
                        elsif (decoders_busy(4) = '0') then
                            sm_chan         <= "100";
                            sm_dvs          <= "00010000";
                            stream_drop     <= '0'; 
                        elsif (decoders_busy(5) = '0') then
                            sm_chan         <= "101";
                            sm_dvs          <= "00100000";
                            stream_drop     <= '0'; 
                        elsif (decoders_busy(6) = '0') then
                            sm_chan         <= "110";
                            sm_dvs          <= "01000000";
                            stream_drop     <= '0'; 
                        elsif (decoders_busy(7) = '0') then
                            sm_chan         <= "111";
                            sm_dvs          <= "10000000";
                            stream_drop     <= '0'; 
                        else                                -- All decoders are busy
                            sm_chan         <= "000";
                            sm_dvs          <= (others=>'0');
                            stream_drop     <= '1'; 
                        end if;

                    else
                        if (decoders_busy = X"00") then
                            busy        <= '0';
                        end if;

                        din_d1          <= (others=>'0');
                        din_ns_d1       <= '0'; 
                        din_dv_d1       <= '0';
                        stream_chan_dv  <= '0'; 
                        stream_drop     <= '0'; 

                    end if;


                ------------------------------------------------
                -- Continue sending data. 
                -- Change channel on each each new stream.
                -- Set sm_dvs to all zero and set stream_drop=1 if
                -- no decode engines are available
                ------------------------------------------------
                when S_RUN  =>

                    if (din_dv = '1') then

                        din_d1      <= din;
                        din_ns_d1   <= din_ns; 
                        din_dv_d1   <= '1';

                        if (din_ns = '1') then 

                            stream_chan_dv  <= '1'; 

                            if    (decoders_busy(0) = '0') then
                                sm_chan         <= "000";
                                sm_dvs          <= "00000001";
                                stream_drop     <= '0'; 
                            elsif (decoders_busy(1) = '0') then
                                sm_chan         <= "001";
                                sm_dvs          <= "00000010";
                                stream_drop     <= '0'; 
                            elsif (decoders_busy(2) = '0') then
                                sm_chan         <= "010";
                                sm_dvs          <= "00000100";
                                stream_drop     <= '0'; 
                            elsif (decoders_busy(3) = '0') then
                                sm_chan         <= "011";
                                sm_dvs          <= "00001000";
                                stream_drop     <= '0'; 
                            elsif (decoders_busy(4) = '0') then
                                sm_chan         <= "100";
                                sm_dvs          <= "00010000";
                                stream_drop     <= '0'; 
                            elsif (decoders_busy(5) = '0') then
                                sm_chan         <= "101";
                                sm_dvs          <= "00100000";
                                stream_drop     <= '0'; 
                            elsif (decoders_busy(6) = '0') then
                                sm_chan         <= "110";
                                sm_dvs          <= "01000000";
                                stream_drop     <= '0'; 
                            elsif (decoders_busy(7) = '0') then
                                sm_chan         <= "111";
                                sm_dvs          <= "10000000";
                                stream_drop     <= '0'; 
                            else                                -- All decoders are busy
                                sm_chan         <= "000";
                                sm_dvs          <= (others=>'0');
                                stream_drop     <= '1'; 
                            end if;
                        else
                            stream_chan_dv  <= '0'; 
                            stream_drop     <= '0'; 
                        end if;

                    else
                        din_d1          <= (others=>'0');
                        din_ns_d1       <= '0'; 
                        din_dv_d1       <= '0';
                        stream_chan_dv  <= '0'; 
                        stream_drop     <= '0'; 
                    end if;


                ------------------------------------------------
                -- Error state
                ------------------------------------------------
                when others =>

                    state           <= S_IDLE;
                    din_ns_d1       <= '0'; 
                    din_d1          <= (others=>'0');
                    din_dv_d1       <= '0';
                    stream_chan_dv  <= '0'; 
                    stream_drop     <= '0'; 

            end case;

        end if;

    end process;


    -----------------------------------------------------------------------------------
    -- Output signals
    -----------------------------------------------------------------------------------
    pr_dout : process (reset, clk)
    begin
        if (reset='1') then

            dout        <= (others=>'0');
            dout_ns     <= '0'; 
            dout_chan   <= (others=>'0'); 
            dout_dvs    <= (others=>'0');

        elsif rising_edge(clk) then

            if (din_dv_d1 = '1') then

                dout        <= din_d1;
                dout_ns     <= din_ns_d1; 
                dout_dvs    <= sm_dvs;
                dout_chan   <= sm_chan;
                
            else

                dout        <= (others=>'0');
                dout_ns     <= '0'; 
                dout_dvs    <= (others=>'0');

            end if;

        end if;

    end process;

end rtl;

