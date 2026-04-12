-------------------------------------------------------------------------------
-- File       : decode_engine.vhd
-------------------------------------------------------------------------------
-- [Filename]       decode_engine.vhd [RTL]
-- [Project]        Stream Decoder for RD53B data in an FPGA
-- [Author]         G. Jones
-- [Language]       VHDL
-- [Created]        
-- [Description]    Decode a single stream of compressed/encoded addresses, hitmaps, ToTs.
-- 
-- Address length can vary between 2,8,10,16.
-- Encoded hitmap length can vary from 4 to 30 bits
-- ToT length can vary from 4 to 64 bits in steps of 4.
-- Min encoded hit length is 2+4+4 = 10.
-- Max encoded hit length is 16+30+64 = 110.
-- 
-- Input is over a 63-bit bus. 
-- Data is initially buffered in a FIFO and then read out into a shift register (sreg) whenever the register
-- has space for 63 new bits. Initially 3 words are read into sreg[188:126], sreg[125:63] and sreg[62:0]
-- After each hit is decoded, from the sreg MSBs, we check to see if the 
-- sreg can be shifted left by 63 bits so that a new word can be read from the input FIFO.
-- Shifts can only occur in blocks of 63. The sreg_ptr keeps track of where the next hits address field starts.
-- The sreg_ptr starts at sreg[188]. If a 10-bit hit is consumed then sreg_ptr will be moved to (188-10) 178.
-- A second hit of 42 bits (say) will move the pointer to (178-48) 136.
-- A third hit of 31 bits (say) will move the pointer to 105. Once the pointer is below (188-63) = 125 then
-- sreg will be shifted left by 63 bits, a new word will be read from the FIFO into sreg[62:0] and the pointer
-- moves to (105+63) 168.  This is the location of the MSB of the next address block. 
--
-- If the MSBs are 6, or more, zeros then there are no more hits and this marks the end of the stream.
-- *** Internal (11-bit beginning "111") internal tags are not currently supported
-------------------------------------------------------------------------------
library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity decode_engine is
port (
    reset           : in    std_logic;
    clk             : in    std_logic;

    busy            : out   std_logic;                      -- Status. Set once a 'NS=1' is seen. Cleared when end of stream is detected
    ready           : out   std_logic;                      -- Set low when input FIFO approaches full
    errors          : out   std_logic_vector( 2 downto 0);  -- Status. FIFO over threshold, FIFO overflow, underflow.

    -- Options. '1' to enable
    reg_en_chip_id  : in    std_logic;                      -- '1' means that channel_id is in stream immediately after NS
    reg_en_encode   : in    std_logic;                      -- '1' means that hitmap is encoded. '0' = Always 16 bits
    reg_en_tot      : in    std_logic;                      -- '1' means that  there are ToT values in the data
    reg_en_eos      : in    std_logic;                      -- '1'  Enable min 6 zeros output to mark end of stream

    -- Encoded data input
    din             : in    std_logic_vector(62 downto 0);  -- Input encoded stream data
    din_ns          : in    std_logic;                      -- NS (new_stream) bit
    din_chan        : in    std_logic_vector( 2 downto 0);  -- Encoded data channel number (0-7)
    din_dv          : in    std_logic;                      -- Data valid

    -- Data identification outputs 
    dout_chip_id    : out   std_logic_vector( 1 downto 0);  -- Channel ID captured from beginning of data stream (optional)
    dout_tag        : out   std_logic_vector( 7 downto 0);  -- Tag 8-bit captured from beginning of data stream
    dout_eos        : out   std_logic;
    dout_eoe        : out   std_logic;

    -- Decoded hit fields 
    dout_ccol       : out   std_logic_vector( 5 downto 0);
    dout_qrow       : out   std_logic_vector( 7 downto 0);
    dout_hitmap     : out   std_logic_vector(15 downto 0);
    dout_tot        : out   std_logic_vector(63 downto 0);
    dout_dv         : out   std_logic 
);
end decode_engine;

architecture rtl of decode_engine is

-- Register to hold up to three words read from input FIFO.  3 x 63 = 189
-- An encoded 'hit' can be as short as 10 bits and as long as 110
constant  C_SIZE_SREG       : integer := 3*63;     
signal sreg                 : std_logic_vector(C_SIZE_SREG-1 downto 0);

-- State machine variable for updating sreg, ptr_sreg
type t_state  is (
    S_IDLE          ,   -- Waiting for a new stream. Load first word into reg_shift
    S_WAIT_INIT0    ,   -- 
    S_INIT0         ,   -- Load second word into sreg
    S_WAIT_INIT1    ,   -- 
    S_INIT1         ,   -- Load third word of sreg
    S_ADDR          ,   -- Decode the address field (ccol, islast, isneighbor, qrow)
    S_WAIT_DEC      ,   -- Wait N clock cycles for 30-bit encoded hit data to be decoded 
    S_TOT           ,   -- Extract ToT bits. Update reg_shift and ptr_shift 
    S_EOS
);
signal state                : t_state;  
constant  C_PIPELEN_DECODE  : integer := 5;                         -- Length of hitmap decoder pipeline
signal sm_cnt               : integer range 0 to C_PIPELEN_DECODE;  -- Counter used in state machine for decoder pipeline delay
signal ptr_sreg             : integer range 0 to 188;               -- Pointer to current decode point. Updated by state machine
signal nbits_tot            : integer range 0 to 64;                -- Number of bits in ToT field
signal is_last              : std_logic; 
signal is_neighbor          : std_logic; 
signal sm_rd_fifo           : std_logic; 
signal start_sm             : std_logic; 


-- A reminder that this block will eventually handle the decoding of multiple streams with one ROM decoder
--type t_states is array (G_ENGINES-1 downto 0) of t_state;
--signal states               : t_states;

-- Interface to hitmap decoder
signal dh_din               : std_logic_vector(29 downto 0);    --  Contains input hitmap in MSBs. Actual size is unknown. 5 bits min, 30 bits max
signal dh_din_chan          : std_logic_vector( 3 downto 0);    --  Channel number of input hitmap data
signal dh_din_dv            : std_logic;                        --  Input data valid
-- Out
signal dh_hitmap_out        : std_logic_vector(15 downto 0);    --  Decoded hitmap
signal dh_hitmap_length     : std_logic_vector( 4 downto 0);    --  Actual length of the compressed input hitmap (4 to 30)
signal dh_hitmap_nbits      : std_logic_vector( 4 downto 0);    --  Number of bits set in the decoded hitmap. (1 to 16)
signal dh_hitmap_out_chan   : std_logic_vector( 3 downto 0);    --  Channel number of output hitmap
signal dh_hitmap_out_dv     : std_logic;                        --  Output data valid

-- Registers to hold outputs from address, hitmap and ToT decoding
signal reg_chip_id          : std_logic_vector( 1 downto 0);    -- Captured at beginning of the stream (opt)
signal reg_tag              : std_logic_vector( 7 downto 0);    -- Captured at beginning of the stream
signal reg_ccol             : std_logic_vector( 5 downto 0);
signal reg_qrow             : std_logic_vector( 7 downto 0);
signal reg_hitmap           : std_logic_vector(15 downto 0);
signal reg_tot              : std_logic_vector(63 downto 0);
--signal reg_eos              : std_logic;
signal reg_hitmap_nbits     : std_logic_vector( 4 downto 0);    --  Number of bits set in the decoded hitmap. (1 to 16)

signal fifo_ibuf_din        : std_logic_vector(63 downto 0);
signal fifo_ibuf_dout       : std_logic_vector(63 downto 0);
signal fifo_ibuf_uflow      : std_logic;
signal fifo_ibuf_oflow      : std_logic;
signal fifo_ibuf_full       : std_logic;
signal fifo_ibuf_empty      : std_logic;
signal fifo_ibuf_level      : std_logic_vector( 9 downto 0);
signal fifo_ibuf_wr_en      : std_logic;
signal fifo_ibuf_wr         : std_logic;

signal dbg_6zeros           : std_logic_vector( 5 downto 0);
signal zero64               : std_logic_vector(63 downto 0);

--attribute mark_debug                    : string;
--attribute keep                          : string;
--attribute mark_debug of din             : signal is "true";  -- std_logic_vector(62 downto 0);
--attribute mark_debug of din_ns          : signal is "true";  -- std_logic;                    
--attribute mark_debug of din_chan        : signal is "true";  -- std_logic_vector( 2 downto 0);
--attribute mark_debug of din_dv          : signal is "true";  -- std_logic;                    
--attribute mark_debug of dout_ccol       : signal is "true";  -- std_logic_vector( 5 downto 0);
--attribute mark_debug of dout_qrow       : signal is "true";  -- std_logic_vector( 7 downto 0);
--attribute mark_debug of dout_hitmap     : signal is "true";  -- std_logic_vector(15 downto 0);
--attribute mark_debug of dout_tot        : signal is "true";  -- std_logic_vector(63 downto 0);
--attribute mark_debug of dout_dv         : signal is "true";  -- std_logic 
--attribute mark_debug of state           : signal is "true";  -- t_state;  
--attribute mark_debug of is_last         : signal is "true";  -- std_logic; 
--attribute mark_debug of is_neighbor     : signal is "true";  -- std_logic; 
--attribute mark_debug of sm_rd_fifo      : signal is "true";  -- std_logic; 
--attribute mark_debug of start_sm        : signal is "true";  -- std_logic; 

begin      
    zero64          <= (others=>'0');
    start_sm        <= '1';
    fifo_ibuf_din   <= din_ns & din; 
    fifo_ibuf_wr    <= fifo_ibuf_wr_en and din_dv;

    -----------------------------------------------------------
    -- 64b x 512 FIFO buffer for 63-bit input data and NS flag
    -- This FIFO should be reduced in size if possible. (8K bits?)
    -----------------------------------------------------------
    u_fifo_buf : entity work.fifo_512x64b
    port map(
        clk         => clk                      ,
        srst        => reset                    ,
        din         => fifo_ibuf_din            ,   -- input wire [63 : 0] din
        wr_en       => fifo_ibuf_wr             ,

        rd_en       => sm_rd_fifo               , 
        dout        => fifo_ibuf_dout           ,   -- output wire [63 : 0] dout
        
        underflow   => fifo_ibuf_uflow          ,
        overflow    => fifo_ibuf_oflow          ,
        full        => fifo_ibuf_full           ,
        empty       => fifo_ibuf_empty          ,
        data_count  => fifo_ibuf_level              -- Number of words stored in FIFO

    );
    -- Error output
    errors(0)   <= fifo_ibuf_uflow;
    errors(1)   <= fifo_ibuf_oflow;
    errors(2)   <= not(fifo_ibuf_wr_en);


    -----------------------------------------------------------------------------------
    -- FIFO data is read into a shift reg that can hold 3x 63-bit words (188:0)
    -- Initially 3 words are read into the buffer and a pointer is set to bit 188. 
    -- The first word in [188:126], the second into [125:63] and the third into [62:0].
    -- As variable sized chunks of data are decoded the pointer is moved down the buffer.
    -- The data is shifted 63 bits left in the buffer (MSB-wards)and FIFO data is read 
    -- into the LSBs when the current buffer pointer value is past the most significant
    -- 63 bits i.e. < 126
    -- The buffer pointer will then also be increased by 63.
    -- Initial buffer pointer, maintained by s.m.,  is 188
    -----------------------------------------------------------------------------------
    -- State machine to maintain the shift reg and current data pointer.
    -- Sends encoded hit data to the decoder block. 
    -- Parses the address fields.
    -- Outputs the ToT bits
    -- Detects 'end-of-stream' (6 zeros) in the S_ADDR state.
    -----------------------------------------------------------------------------------
    pr_sm : process (reset, clk)
    variable v_orphans  : std_logic_vector( 5 downto 0);
    begin
        if (reset='1') then
            state           <= S_IDLE;
            sm_rd_fifo      <= '0';
            ptr_sreg        <= 188;
            sreg            <= (others=>'0');

            is_neighbor     <= '0';
            is_last         <= '0';
            dh_din          <= (others=>'0');
            dh_din_chan     <= (others=>'0');
            dh_din_dv       <= '0';

            reg_chip_id         <= (others=>'0'); 
            reg_tag             <= (others=>'0');
            reg_ccol            <= (others=>'0');
            reg_qrow            <= (others=>'0');
            reg_hitmap          <= (others=>'0');
            reg_hitmap_nbits    <= (others=>'0');
            reg_tot             <= (others=>'0');
            dbg_6zeros          <= "XXXXXX";
            dout_eos            <= '0';

        elsif rising_edge(clk) then

            dh_din_dv   <= '0'; 
            sm_rd_fifo  <= '0';

            case state is

                ------------------------------------------------
                -- Wait for the start of a new stream. The 'start_sm' bit allows
                -- multiple engines to be offset from each other. (Future feature)
                --  Load first word into sreg
                --  Capture ch_id, tag and first hit address fields
                --  Detect EOS
                ------------------------------------------------
                when S_IDLE   =>
                
                    busy        <= '0';

                    if (fifo_ibuf_empty = '0') and (fifo_ibuf_dout(63) = '1') and (start_sm = '1') then 

                        sreg(188 downto 126)    <= fifo_ibuf_dout(62 downto 0);
                        sm_rd_fifo              <= '1';
                        
                        if (reg_en_chip_id = '1') then
                            reg_chip_id     <= fifo_ibuf_dout(62 downto 61);
                            reg_tag         <= fifo_ibuf_dout(60 downto 53);
                            v_orphans       := fifo_ibuf_dout(52 downto 47);     -- Six zeros marks end of stream

                            reg_ccol        <= fifo_ibuf_dout(52 downto 47);
                            is_last         <= fifo_ibuf_dout(46);
                            is_neighbor     <= fifo_ibuf_dout(45);
                            reg_qrow        <= fifo_ibuf_dout(44 downto 37);
                            ptr_sreg        <= 188-26;  -- 26-bit header if chan_id included
                        else
                            reg_chip_id     <= (others=>'0');
                            reg_tag         <= fifo_ibuf_dout(62 downto 55);
                            v_orphans       := fifo_ibuf_dout(54 downto 49);     -- Six zeros marks end of stream
                            
                            reg_ccol        <= fifo_ibuf_dout(54 downto 49);
                            is_last         <= fifo_ibuf_dout(48);
                            is_neighbor     <= fifo_ibuf_dout(47);
                            reg_qrow        <= fifo_ibuf_dout(46 downto 39);
                            ptr_sreg        <= 188-24;  -- 24-bit header if no chan_id
                        end if;
                                                                                          
                        if (v_orphans = "000000") then
                            state           <= S_EOS;
                            dout_eos        <= '1';
                        else    
                            state           <= S_WAIT_INIT0;
                            dout_eos        <= '0';
                        end if;
                        busy    <= '1';
                        
                    else
                        -- Read words from FIFO that do not have NS bit set. Junk?
                        if (fifo_ibuf_empty = '0') and (fifo_ibuf_dout(63) = '0') then 
                            sm_rd_fifo  <= '1';
                        else
                            sm_rd_fifo  <= '0';
                        end if;
                        
                        ptr_sreg    <= 188;
                        sreg        <= (others=>'0');
                        dout_eos    <= '0';

                    end if;

                    dbg_6zeros      <= sreg(ptr_sreg downto ptr_sreg-5);


                when S_WAIT_INIT0   =>
                    state           <= S_INIT0;
                    dbg_6zeros      <= sreg(ptr_sreg downto ptr_sreg-5);

               
               ------------------------------------------------
               -- Load second word into sreg
               ------------------------------------------------
                when S_INIT0   =>

                    if (fifo_ibuf_empty = '0') then

                        sreg(125 downto 63)     <= fifo_ibuf_dout(62 downto 0);
                        sm_rd_fifo              <= '1';
                        state                   <= S_WAIT_INIT1;

                    else
                        sm_rd_fifo  <= '0';
                    end if;

                    dbg_6zeros      <= sreg(ptr_sreg downto ptr_sreg-5);


                when S_WAIT_INIT1   =>
                    state           <= S_INIT1;
                    dbg_6zeros      <= sreg(ptr_sreg downto ptr_sreg-5);
               
               ------------------------------------------------
               -- Load third word into sreg
               ------------------------------------------------
                when S_INIT1   =>

                    if (fifo_ibuf_empty = '0') then

                        sreg(62 downto 0)       <= fifo_ibuf_dout(62 downto 0);
                        sm_rd_fifo              <= '1';

                        -- Send 30-bit encoded hitmap to decoder
                        dh_din          <= sreg(ptr_sreg downto (ptr_sreg-29));
                      --dh_din_chan     <= (others=>'0');
                        dh_din_dv       <= '1';
                        sm_cnt          <= 0;
                        state           <= S_WAIT_DEC;      -- No need to decode address after init. 

                    else
                        sm_rd_fifo  <= '0';
                    end if;

                    dbg_6zeros      <= sreg(ptr_sreg downto ptr_sreg-5);


                ------------------------------------------------
                -- Decode address fields. 
                -- EOS if 6 zeros 
                -- Send next 30 bits to hitmap decoder.
                -- Update ptr_sreg to MSB of encoded hitmap.
                ------------------------------------------------
                when S_ADDR  =>

                    if (is_last = '1') then -- Previous is_last was set so update ccol

                        if (sreg(ptr_sreg downto ptr_sreg-5) = "000000") then -- End of sequence marked by six zeros in ccol field
                            state       <= S_EOS;
                            dout_eos    <= '1';
                        else
                            reg_ccol    <= sreg(ptr_sreg downto (ptr_sreg-5));
                            is_last     <= sreg(ptr_sreg-6);
                            is_neighbor <= sreg(ptr_sreg-7);
                            dout_eos    <= '0';

                            if (sreg(ptr_sreg-7) = '0') then    -- 'is_neighbor'            -- Update qrow
                                reg_qrow    <= sreg((ptr_sreg-8)  downto (ptr_sreg-15));
                                if (ptr_sreg-16-29 >= 0) then
                                    dh_din      <= sreg((ptr_sreg-16) downto (ptr_sreg-16-29)); -- Send 30-bit encoded hitmap to decoder
                                else
                                    -- Vivado is unable to synthesise the line below so a case statement must be used
                                    -- dh_din      <= sreg((ptr_sreg-16) downto 0) & zero64((28-(ptr_sreg-16)) downto 0); -- Pad 30-bit encoded hitmap with zeros
                                    case (ptr_sreg-16) is  -- There must be at least 5 bits for the encoded hitmap and 4 bits for the ToT so start case at 8
                                        when  8 =>  dh_din  <= sreg( 8 downto 0) & zero64(28-8  downto 0);
                                        when  9 =>  dh_din  <= sreg( 9 downto 0) & zero64(28-9  downto 0);
                                        when 10 =>  dh_din  <= sreg(10 downto 0) & zero64(28-10 downto 0);
                                        when 11 =>  dh_din  <= sreg(11 downto 0) & zero64(28-11 downto 0);
                                        when 12 =>  dh_din  <= sreg(12 downto 0) & zero64(28-12 downto 0);
                                        when 13 =>  dh_din  <= sreg(13 downto 0) & zero64(28-13 downto 0);
                                        when 14 =>  dh_din  <= sreg(14 downto 0) & zero64(28-14 downto 0);
                                        when 15 =>  dh_din  <= sreg(15 downto 0) & zero64(28-15 downto 0);
                                        when 16 =>  dh_din  <= sreg(16 downto 0) & zero64(28-16 downto 0);
                                        when 17 =>  dh_din  <= sreg(17 downto 0) & zero64(28-17 downto 0);
                                        when 18 =>  dh_din  <= sreg(18 downto 0) & zero64(28-18 downto 0);
                                        when 19 =>  dh_din  <= sreg(19 downto 0) & zero64(28-19 downto 0);
                                        when 20 =>  dh_din  <= sreg(20 downto 0) & zero64(28-20 downto 0);
                                        when 21 =>  dh_din  <= sreg(21 downto 0) & zero64(28-21 downto 0);
                                        when 22 =>  dh_din  <= sreg(22 downto 0) & zero64(28-22 downto 0);
                                        when 23 =>  dh_din  <= sreg(23 downto 0) & zero64(28-23 downto 0);
                                        when 24 =>  dh_din  <= sreg(24 downto 0) & zero64(28-24 downto 0);
                                        when 25 =>  dh_din  <= sreg(25 downto 0) & zero64(28-25 downto 0);
                                        when 26 =>  dh_din  <= sreg(26 downto 0) & zero64(28-26 downto 0);
                                        when 27 =>  dh_din  <= sreg(27 downto 0) & zero64(28-27 downto 0);
                                        when 28 =>  dh_din  <= sreg(28 downto 0) & '0';
                                        when 29 =>  dh_din  <= sreg(29 downto 0);
                                        when others  =>  dh_din  <= zero64(29 downto 0);
                                    end case;
                                end if;
                                
                                ptr_sreg    <= ptr_sreg - 16;
                            else    
                                reg_qrow    <= std_logic_vector(unsigned(reg_qrow) + 1);    -- Increment qrow
                                if (ptr_sreg-8-29 >= 0) then
                                    dh_din      <= sreg((ptr_sreg-8) downto (ptr_sreg-8-29));   -- Send 30-bit encoded hitmap to decoder
                                else
                                    -- Vivado is unable to synthesise the line below so a case statement must be used
                                    -- dh_din      <= sreg((ptr_sreg-8) downto 0) & zero64((28-(ptr_sreg-8)) downto 0); -- Pad 30-bit encoded hitmap with zeros
                                    case (ptr_sreg-8) is  -- There must be at least 5 bits for the encoded hitmap and 4 bits for the ToT so start case at 8
                                        when  8 =>  dh_din  <= sreg( 8 downto 0) & zero64(28-8  downto 0);
                                        when  9 =>  dh_din  <= sreg( 9 downto 0) & zero64(28-9  downto 0);
                                        when 10 =>  dh_din  <= sreg(10 downto 0) & zero64(28-10 downto 0);
                                        when 11 =>  dh_din  <= sreg(11 downto 0) & zero64(28-11 downto 0);
                                        when 12 =>  dh_din  <= sreg(12 downto 0) & zero64(28-12 downto 0);
                                        when 13 =>  dh_din  <= sreg(13 downto 0) & zero64(28-13 downto 0);
                                        when 14 =>  dh_din  <= sreg(14 downto 0) & zero64(28-14 downto 0);
                                        when 15 =>  dh_din  <= sreg(15 downto 0) & zero64(28-15 downto 0);
                                        when 16 =>  dh_din  <= sreg(16 downto 0) & zero64(28-16 downto 0);
                                        when 17 =>  dh_din  <= sreg(17 downto 0) & zero64(28-17 downto 0);
                                        when 18 =>  dh_din  <= sreg(18 downto 0) & zero64(28-18 downto 0);
                                        when 19 =>  dh_din  <= sreg(19 downto 0) & zero64(28-19 downto 0);
                                        when 20 =>  dh_din  <= sreg(20 downto 0) & zero64(28-20 downto 0);
                                        when 21 =>  dh_din  <= sreg(21 downto 0) & zero64(28-21 downto 0);
                                        when 22 =>  dh_din  <= sreg(22 downto 0) & zero64(28-22 downto 0);
                                        when 23 =>  dh_din  <= sreg(23 downto 0) & zero64(28-23 downto 0);
                                        when 24 =>  dh_din  <= sreg(24 downto 0) & zero64(28-24 downto 0);
                                        when 25 =>  dh_din  <= sreg(25 downto 0) & zero64(28-25 downto 0);
                                        when 26 =>  dh_din  <= sreg(26 downto 0) & zero64(28-26 downto 0);
                                        when 27 =>  dh_din  <= sreg(27 downto 0) & zero64(28-27 downto 0);
                                        when 28 =>  dh_din  <= sreg(28 downto 0) & '0';
                                        when 29 =>  dh_din  <= sreg(29 downto 0);
                                        when others  =>  dh_din  <= zero64(29 downto 0);
                                    end case;
                                end if;
                                
                                ptr_sreg    <= ptr_sreg - 8;
                            end if;
                        
                            state           <= S_WAIT_DEC;

                        end if;

                    else    -- Keep current ccol. Not in stream

                        is_last     <= sreg(ptr_sreg);
                        is_neighbor <= sreg(ptr_sreg-1);
                        dout_eos    <= '0';

                        if (sreg(ptr_sreg-1) = '0') then    -- 'is_neighbor'            -- Update qrow
                            reg_qrow    <= sreg((ptr_sreg-2)  downto (ptr_sreg-9));
                            if (ptr_sreg-10-29 >= 0) then
                                dh_din      <= sreg((ptr_sreg-10) downto (ptr_sreg-10-29)); -- Send 30-bit encoded hitmap to decoder
                            else
                                -- Vivado is unable to synthesise the line below so a case statement must be used
                                -- dh_din      <= sreg((ptr_sreg-16) downto 0) & zero64((28-(ptr_sreg-16)) downto 0); -- Pad 30-bit encoded hitmap with zeros
                                case (ptr_sreg-10) is  -- There must be at least 5 bits for the encoded hitmap and 4 bits for the ToT so start case at 8
                                    when  8 =>  dh_din  <= sreg( 8 downto 0) & zero64(28-8  downto 0);
                                    when  9 =>  dh_din  <= sreg( 9 downto 0) & zero64(28-9  downto 0);
                                    when 10 =>  dh_din  <= sreg(10 downto 0) & zero64(28-10 downto 0);
                                    when 11 =>  dh_din  <= sreg(11 downto 0) & zero64(28-11 downto 0);
                                    when 12 =>  dh_din  <= sreg(12 downto 0) & zero64(28-12 downto 0);
                                    when 13 =>  dh_din  <= sreg(13 downto 0) & zero64(28-13 downto 0);
                                    when 14 =>  dh_din  <= sreg(14 downto 0) & zero64(28-14 downto 0);
                                    when 15 =>  dh_din  <= sreg(15 downto 0) & zero64(28-15 downto 0);
                                    when 16 =>  dh_din  <= sreg(16 downto 0) & zero64(28-16 downto 0);
                                    when 17 =>  dh_din  <= sreg(17 downto 0) & zero64(28-17 downto 0);
                                    when 18 =>  dh_din  <= sreg(18 downto 0) & zero64(28-18 downto 0);
                                    when 19 =>  dh_din  <= sreg(19 downto 0) & zero64(28-19 downto 0);
                                    when 20 =>  dh_din  <= sreg(20 downto 0) & zero64(28-20 downto 0);
                                    when 21 =>  dh_din  <= sreg(21 downto 0) & zero64(28-21 downto 0);
                                    when 22 =>  dh_din  <= sreg(22 downto 0) & zero64(28-22 downto 0);
                                    when 23 =>  dh_din  <= sreg(23 downto 0) & zero64(28-23 downto 0);
                                    when 24 =>  dh_din  <= sreg(24 downto 0) & zero64(28-24 downto 0);
                                    when 25 =>  dh_din  <= sreg(25 downto 0) & zero64(28-25 downto 0);
                                    when 26 =>  dh_din  <= sreg(26 downto 0) & zero64(28-26 downto 0);
                                    when 27 =>  dh_din  <= sreg(27 downto 0) & zero64(28-27 downto 0);
                                    when 28 =>  dh_din  <= sreg(28 downto 0) & '0';
                                    when 29 =>  dh_din  <= sreg(29 downto 0);
                                    when others  =>  dh_din  <= zero64(29 downto 0);
                                end case;
                            end if;
                            ptr_sreg    <= ptr_sreg - 10;
                        else    
                            reg_qrow    <= std_logic_vector(unsigned(reg_qrow) + 1);    -- Increment qrow
                            if (ptr_sreg-2-29 >= 0) then
                                dh_din      <= sreg((ptr_sreg-2) downto (ptr_sreg-2-29)); -- Send 30-bit encoded hitmap to decoder
                            else
                                -- Vivado is unable to synthesise the line below so a case statement must be used
                                -- dh_din      <= sreg((ptr_sreg-2) downto 0) & zero64((28-(ptr_sreg-2)) downto 0); -- Pad 30-bit encoded hitmap with zeros
                                case (ptr_sreg-2) is  -- There must be at least 5 bits for the encoded hitmap and 4 bits for the ToT so start case at 8
                                    when  8 =>  dh_din  <= sreg( 8 downto 0) & zero64(28-8  downto 0);
                                    when  9 =>  dh_din  <= sreg( 9 downto 0) & zero64(28-9  downto 0);
                                    when 10 =>  dh_din  <= sreg(10 downto 0) & zero64(28-10 downto 0);
                                    when 11 =>  dh_din  <= sreg(11 downto 0) & zero64(28-11 downto 0);
                                    when 12 =>  dh_din  <= sreg(12 downto 0) & zero64(28-12 downto 0);
                                    when 13 =>  dh_din  <= sreg(13 downto 0) & zero64(28-13 downto 0);
                                    when 14 =>  dh_din  <= sreg(14 downto 0) & zero64(28-14 downto 0);
                                    when 15 =>  dh_din  <= sreg(15 downto 0) & zero64(28-15 downto 0);
                                    when 16 =>  dh_din  <= sreg(16 downto 0) & zero64(28-16 downto 0);
                                    when 17 =>  dh_din  <= sreg(17 downto 0) & zero64(28-17 downto 0);
                                    when 18 =>  dh_din  <= sreg(18 downto 0) & zero64(28-18 downto 0);
                                    when 19 =>  dh_din  <= sreg(19 downto 0) & zero64(28-19 downto 0);
                                    when 20 =>  dh_din  <= sreg(20 downto 0) & zero64(28-20 downto 0);
                                    when 21 =>  dh_din  <= sreg(21 downto 0) & zero64(28-21 downto 0);
                                    when 22 =>  dh_din  <= sreg(22 downto 0) & zero64(28-22 downto 0);
                                    when 23 =>  dh_din  <= sreg(23 downto 0) & zero64(28-23 downto 0);
                                    when 24 =>  dh_din  <= sreg(24 downto 0) & zero64(28-24 downto 0);
                                    when 25 =>  dh_din  <= sreg(25 downto 0) & zero64(28-25 downto 0);
                                    when 26 =>  dh_din  <= sreg(26 downto 0) & zero64(28-26 downto 0);
                                    when 27 =>  dh_din  <= sreg(27 downto 0) & zero64(28-27 downto 0);
                                    when 28 =>  dh_din  <= sreg(28 downto 0) & '0';
                                    when 29 =>  dh_din  <= sreg(29 downto 0);
                                    when others  =>  dh_din  <= zero64(29 downto 0);
                                end case;
                            end if;
                            ptr_sreg    <= ptr_sreg - 2;
                        end if;
                        
                        state           <= S_WAIT_DEC;
                    end if;

                    dbg_6zeros      <= sreg(ptr_sreg downto ptr_sreg-5);
                    dh_din_dv       <= '1';


                ------------------------------------------------
                -- Wait for decoder output pipeline delay.
                -- Check to see if ptr_sreg is below the shift point so that 
                -- sreg can be shifted and loaded with another word from the FIFO
                ------------------------------------------------
                when S_WAIT_DEC =>

                    if (sm_cnt = C_PIPELEN_DECODE) then
                            
                        reg_hitmap      <= dh_hitmap_out;                           -- Decoded hitmap
                        nbits_tot       <= 4*to_integer(unsigned(dh_hitmap_nbits));    -- 4*Number of bits set in the decoded hitmap. (1 to 16) -> 4 to 64
                        reg_hitmap_nbits<= dh_hitmap_nbits;
                        ptr_sreg        <= ptr_sreg - to_integer(unsigned(dh_hitmap_length));   -- Move pointer to MSB of ToTs

                        state           <= S_TOT;
                        sm_cnt          <= 0;
                        sm_rd_fifo      <= '0';
                    else
                        sm_cnt          <= sm_cnt + 1;

                        -- On these two stages, check to see if sreg can be shifted and loaded with another word from the FIFO
                        if ((sm_cnt = 1) or (sm_cnt = 3)) then

                            if ((ptr_sreg < 126) and (fifo_ibuf_empty = '0')) then
                                sreg(188 downto 63)     <= sreg(125 downto 0);
                                sreg( 62 downto  0)     <= fifo_ibuf_dout(62 downto 0);
                                sm_rd_fifo              <= '1';
                                ptr_sreg                <= ptr_sreg + 63;   -- Update pointer 
                            else
                                sm_rd_fifo              <= '0';
                            end if;

                        end if;

                    end if;

                    dbg_6zeros  <= sreg(ptr_sreg downto ptr_sreg-5);

                ------------------------------------------------
                -- Extract ToT field, if it is in use.
                -- Move pointer to start of next address field.
                ------------------------------------------------
                when S_TOT =>

                    if (reg_en_tot = '1') then

                        -- Extract 64 ToT bits.
                        -- This can be a problem in the last word when ptr_sreg can be < 64. In that case, pad with zeros
                        if (ptr_sreg < 63) and (fifo_ibuf_empty = '1') then
                            -- NOT SYNTHESIZABLE to_unsigned(0, 63-ptr_sreg)
                            --reg_tot     <= sreg(ptr_sreg downto 0) & std_logic_vector(to_unsigned(0, 63-ptr_sreg));   
                            -- TODO Doesn't like fact that ptr_sreg could be 188?
                            --reg_tot     <= std_logic_vector(shift_left(unsigned(sreg(ptr_sreg downto 0)), (63-ptr_sreg)));
                            case ptr_sreg is
                                when  0     => reg_tot     <= sreg(          0) & zero64(62 downto 0);
                                when  1     => reg_tot     <= sreg( 1 downto 0) & zero64(61 downto 0);
                                when  2     => reg_tot     <= sreg( 2 downto 0) & zero64(60 downto 0);
                                when  3     => reg_tot     <= sreg( 3 downto 0) & zero64(59 downto 0);
                                when  4     => reg_tot     <= sreg( 4 downto 0) & zero64(58 downto 0);
                                when  5     => reg_tot     <= sreg( 5 downto 0) & zero64(57 downto 0);
                                when  6     => reg_tot     <= sreg( 6 downto 0) & zero64(56 downto 0);
                                when  7     => reg_tot     <= sreg( 7 downto 0) & zero64(55 downto 0);
                                when  8     => reg_tot     <= sreg( 8 downto 0) & zero64(54 downto 0);
                                when  9     => reg_tot     <= sreg( 9 downto 0) & zero64(53 downto 0);

                                when 10     => reg_tot     <= sreg(10 downto 0) & zero64(52 downto 0);
                                when 11     => reg_tot     <= sreg(11 downto 0) & zero64(51 downto 0);
                                when 12     => reg_tot     <= sreg(12 downto 0) & zero64(50 downto 0);
                                when 13     => reg_tot     <= sreg(13 downto 0) & zero64(49 downto 0);
                                when 14     => reg_tot     <= sreg(14 downto 0) & zero64(48 downto 0);
                                when 15     => reg_tot     <= sreg(15 downto 0) & zero64(47 downto 0);
                                when 16     => reg_tot     <= sreg(16 downto 0) & zero64(46 downto 0);
                                when 17     => reg_tot     <= sreg(17 downto 0) & zero64(45 downto 0);
                                when 18     => reg_tot     <= sreg(18 downto 0) & zero64(44 downto 0);
                                when 19     => reg_tot     <= sreg(19 downto 0) & zero64(43 downto 0);

                                when 20     => reg_tot     <= sreg(20 downto 0) & zero64(42 downto 0);
                                when 21     => reg_tot     <= sreg(21 downto 0) & zero64(41 downto 0);
                                when 22     => reg_tot     <= sreg(22 downto 0) & zero64(40 downto 0);
                                when 23     => reg_tot     <= sreg(23 downto 0) & zero64(39 downto 0);
                                when 24     => reg_tot     <= sreg(24 downto 0) & zero64(38 downto 0);
                                when 25     => reg_tot     <= sreg(25 downto 0) & zero64(37 downto 0);
                                when 26     => reg_tot     <= sreg(26 downto 0) & zero64(36 downto 0);
                                when 27     => reg_tot     <= sreg(27 downto 0) & zero64(35 downto 0);
                                when 28     => reg_tot     <= sreg(28 downto 0) & zero64(34 downto 0);
                                when 29     => reg_tot     <= sreg(29 downto 0) & zero64(33 downto 0);

                                when 30     => reg_tot     <= sreg(30 downto 0) & zero64(32 downto 0);
                                when 31     => reg_tot     <= sreg(31 downto 0) & zero64(31 downto 0);
                                when 32     => reg_tot     <= sreg(32 downto 0) & zero64(30 downto 0);
                                when 33     => reg_tot     <= sreg(33 downto 0) & zero64(29 downto 0);
                                when 34     => reg_tot     <= sreg(34 downto 0) & zero64(28 downto 0);
                                when 35     => reg_tot     <= sreg(35 downto 0) & zero64(27 downto 0);
                                when 36     => reg_tot     <= sreg(36 downto 0) & zero64(26 downto 0);
                                when 37     => reg_tot     <= sreg(37 downto 0) & zero64(25 downto 0);
                                when 38     => reg_tot     <= sreg(38 downto 0) & zero64(24 downto 0);
                                when 39     => reg_tot     <= sreg(39 downto 0) & zero64(23 downto 0);

                                when 40     => reg_tot     <= sreg(40 downto 0) & zero64(22 downto 0);
                                when 41     => reg_tot     <= sreg(41 downto 0) & zero64(21 downto 0);
                                when 42     => reg_tot     <= sreg(42 downto 0) & zero64(20 downto 0);
                                when 43     => reg_tot     <= sreg(43 downto 0) & zero64(19 downto 0);
                                when 44     => reg_tot     <= sreg(44 downto 0) & zero64(18 downto 0);
                                when 45     => reg_tot     <= sreg(45 downto 0) & zero64(17 downto 0);
                                when 46     => reg_tot     <= sreg(46 downto 0) & zero64(16 downto 0);
                                when 47     => reg_tot     <= sreg(47 downto 0) & zero64(15 downto 0);
                                when 48     => reg_tot     <= sreg(48 downto 0) & zero64(14 downto 0);
                                when 49     => reg_tot     <= sreg(49 downto 0) & zero64(13 downto 0);

                                when 50     => reg_tot     <= sreg(50 downto 0) & zero64(12 downto 0);
                                when 51     => reg_tot     <= sreg(51 downto 0) & zero64(11 downto 0);
                                when 52     => reg_tot     <= sreg(52 downto 0) & zero64(10 downto 0);
                                when 53     => reg_tot     <= sreg(53 downto 0) & zero64( 9 downto 0);
                                when 54     => reg_tot     <= sreg(54 downto 0) & zero64( 8 downto 0);
                                when 55     => reg_tot     <= sreg(55 downto 0) & zero64( 7 downto 0);
                                when 56     => reg_tot     <= sreg(56 downto 0) & zero64( 6 downto 0);
                                when 57     => reg_tot     <= sreg(57 downto 0) & zero64( 5 downto 0);
                                when 58     => reg_tot     <= sreg(58 downto 0) & zero64( 4 downto 0);
                                when 59     => reg_tot     <= sreg(59 downto 0) & zero64( 3 downto 0);

                                when 60     => reg_tot     <= sreg(60 downto 0) & zero64( 2 downto 0);
                                when 61     => reg_tot     <= sreg(61 downto 0) & zero64( 1 downto 0);
                                when 62     => reg_tot     <= sreg(62 downto 0) & '0';
                                when 63     => reg_tot     <= sreg(63 downto 0);
                                when others => reg_tot     <= (others=>'0');
                            end case;    
                        else 
                            reg_tot     <= sreg(ptr_sreg downto ptr_sreg-63);       -- Normal ToT selection
                        end if;

                        -- If pointer is low, read data word from FIFO
                        if (ptr_sreg < 126) and (fifo_ibuf_empty = '0') then
                            sreg(188 downto 63)     <= sreg(125 downto 0);
                            sreg( 62 downto  0)     <= fifo_ibuf_dout(62 downto 0);
                            sm_rd_fifo              <= '1';
                            ptr_sreg                <= ptr_sreg - nbits_tot + 63;   -- Update pointer 
                        else
                            ptr_sreg                <= ptr_sreg - nbits_tot;        -- Update pointer 
                        end if;

                    -- No ToT field enabled
                    else
                        reg_tot     <= (others=>'0');
                        
                    end if;
                
                    state       <= S_ADDR;
                    dbg_6zeros  <= sreg(ptr_sreg downto ptr_sreg-5);


                ------------------------------------------------
                -- End of stream 
                ------------------------------------------------
                when S_EOS  =>
                    state       <= S_IDLE;
                    dout_eos    <= '0';
                    dbg_6zeros  <= sreg(ptr_sreg downto ptr_sreg-5);


                when others =>
                    state   <= S_IDLE;

            end case;

        end if;

    end process;


    -----------------------------------------------------------------------------------
    -- Hitmap Decoder 
    -- (4 to 30 bits of input hitmap decoded into an output 16-bit field with its number
    -- of bits set and also the actual length of the original input hitmap
    -----------------------------------------------------------------------------------
    u_hitdecode : entity work.hitdecode 
    port map(
        clk                 => clk                  ,  -- input                        
        reset               => reset                ,  -- input                        

        reg_en_encode       => reg_en_encode        ,  -- input                        

        data_in             => dh_din               ,  -- input   [29:0]              Contains input hitmap in MSBs. Actual size is unknown. 5 bits min, 30 bits max
        data_in_chan        => dh_din_chan          ,  -- input   [ 3:0]              Channel number of input hitmap data
        data_in_dv          => dh_din_dv            ,  -- input                       Input data valid

        hitmap_out          => dh_hitmap_out        ,  -- output  reg [15:0]          Decoded hitmap
        hitmap_length       => dh_hitmap_length     ,  -- output  reg [ 4:0]          Actual length of the compressed input hitmap (4 to 30)
        hitmap_nbits        => dh_hitmap_nbits      ,  -- output  reg [ 4:0]          Number of bits set in the decoded hitmap. (1 to 16)
        hitmap_out_chan     => dh_hitmap_out_chan   ,  -- output  reg [ 3:0]          Channel number of output hitmap
        hitmap_out_dv       => dh_hitmap_out_dv        -- output  reg                 Output data valid
    );


    -----------------------------------------------------------------------------------
    -- Output registers. 
    -- Mask ToT bits that do not contain valid data
    -----------------------------------------------------------------------------------
    pr_dout : process (reset, clk)
    begin
        if (reset='1') then

            dout_chip_id    <= (others=>'0'); 
            dout_tag        <= (others=>'0');
            dout_ccol       <= (others=>'0');
            dout_qrow       <= (others=>'0');
            dout_hitmap     <= (others=>'0');
            dout_tot        <= (others=>'0');
            dout_eoe        <= '0';
          --dout_eos        <= '0'; -- Set directly in state machine process to avoid an additional clock delay
            dout_dv         <= '0';

        elsif rising_edge(clk) then

            -- Output all of the collected fields/bits
            if (state = S_ADDR) then
                
                dout_chip_id    <= reg_chip_id; 
                dout_tag        <= reg_tag;
                dout_ccol       <= reg_ccol;
                dout_qrow       <= reg_qrow;
                dout_hitmap     <= reg_hitmap;
                dout_dv         <= '1';
                
                -- Zero out the unused parts of the ToT bus
                case to_integer(unsigned(reg_hitmap_nbits)) is

                    when  1     =>  dout_tot    <= reg_tot(63 downto 60) & X"000000000000000";
                    when  2     =>  dout_tot    <= reg_tot(63 downto 56) & X"00000000000000";
                    when  3     =>  dout_tot    <= reg_tot(63 downto 52) & X"0000000000000";
                    when  4     =>  dout_tot    <= reg_tot(63 downto 48) & X"000000000000";
                    when  5     =>  dout_tot    <= reg_tot(63 downto 44) & X"00000000000";
                    when  6     =>  dout_tot    <= reg_tot(63 downto 40) & X"0000000000";
                    when  7     =>  dout_tot    <= reg_tot(63 downto 36) & X"000000000";
                    when  8     =>  dout_tot    <= reg_tot(63 downto 32) & X"00000000";
                    when  9     =>  dout_tot    <= reg_tot(63 downto 28) & X"0000000";
                    when 10     =>  dout_tot    <= reg_tot(63 downto 24) & X"000000";
                    when 11     =>  dout_tot    <= reg_tot(63 downto 20) & X"00000";
                    when 12     =>  dout_tot    <= reg_tot(63 downto 16) & X"0000";
                    when 13     =>  dout_tot    <= reg_tot(63 downto 12) & X"000";
                    when 14     =>  dout_tot    <= reg_tot(63 downto  8) & X"00";
                    when 15     =>  dout_tot    <= reg_tot(63 downto  4) & X"0";
                    when 16     =>  dout_tot    <= reg_tot(63 downto  0);
                    when others =>  dout_tot    <= (others=>'0');

                end case;

            else

                dout_chip_id    <= (others=>'0'); 
                dout_tag        <= (others=>'0');
                dout_ccol       <= (others=>'0');
                dout_qrow       <= (others=>'0');
                dout_hitmap     <= (others=>'0');
                dout_tot        <= (others=>'0');
                dout_eoe        <= '0';
                dout_dv         <= '0';

            end if;

        end if;

    end process;


    -----------------------------------------------------------------------------------
    -- Signal to hitmaker when decoding input FIFO is getting full
    -----------------------------------------------------------------------------------
    pr_fifo_ibuf_wr_en : process (reset, clk)
    begin
        if (reset='1') then
            fifo_ibuf_wr_en     <= '1';

        elsif rising_edge(clk) then

            if (unsigned(fifo_ibuf_level) > 500) then   
                fifo_ibuf_wr_en     <= '0';

            else
                fifo_ibuf_wr_en     <= '1';

            end if;

        end if;

    end process;

    -----------------------------------------------------------------------------------
    -- Signal to hitmaker when decoding input FIFO is getting full
    -----------------------------------------------------------------------------------
    pr_ready : process (reset, clk)
    begin
        if (reset='1') then
            ready       <= '0';

        elsif rising_edge(clk) then

            if (unsigned(fifo_ibuf_level) < 256) then   
                ready         <= '1';

            elsif (unsigned(fifo_ibuf_level) > 450) then    -- Back pressure to hitmaker
                ready         <= '0';

            end if;

        end if;

    end process;

end rtl;

