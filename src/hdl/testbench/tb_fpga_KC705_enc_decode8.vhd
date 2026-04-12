-------------------------------------------------------------------------------
-- Author      : Gjones
-------------------------------------------------------------------------------
-- Testbench for testing RD53B output Aurora bus decoding.
-- Uses hitmaker block to generate patterns and compressed data.
-- Contains an eight engine decoder in a KC705 dev board top level FPGA.
-- Testbench compares decoded data against original data.
-------------------------------------------------------------------------------
library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     std.textio.all;

entity  tb_fpga_KC705_enc_decode8 is
end     tb_fpga_KC705_enc_decode8;

architecture struct of tb_fpga_KC705_enc_decode8 is

-- Clock freq expressed in MHz
constant CLK_FREQ_MHZ       : real      := 200.0;
-- Clock period
constant CLK_PER_MHZ        : time      := integer(1.0E+6/(CLK_FREQ_MHZ)) * 1 ps;

signal sim_done             : boolean   := false;

signal clk                  : std_logic := '0';             
signal reset                : std_logic := '1';           

-- Input clock
signal SYSCLK_P             : std_logic := '0'; 
signal SYSCLK_N             : std_logic := '1';

signal CPU_RESET            : std_logic := '1'; -- Reset
signal GPIO_SW_N            : std_logic := '0'; -- start
signal GPIO_SW_S            : std_logic := '0'; -- stop
signal GPIO_SW_E            : std_logic := '0'; -- 
signal GPIO_SW_W            : std_logic := '0'; -- 
signal GPIO_SW_C            : std_logic := '0'; -- 

signal GPIO_DIP_SW0         : std_logic := '1'; -- for reg_hits_per_stream or reg_words_per_stream
signal GPIO_DIP_SW1         : std_logic := '0';
signal GPIO_DIP_SW2         : std_logic := '0';
signal GPIO_DIP_SW3         : std_logic := '0';

-- Outputs
signal GPIO_LED_0_LS        : std_logic; 
signal GPIO_LED_1_LS        : std_logic;
signal GPIO_LED_2_LS        : std_logic;
signal GPIO_LED_3_LS        : std_logic;
signal GPIO_LED_4_LS        : std_logic;
signal GPIO_LED_5_LS        : std_logic;
signal GPIO_LED_6_LS        : std_logic;
signal GPIO_LED_7_LS        : std_logic;
signal DEBUG_OUT            : std_logic_vector( 6 downto 0);

signal dist_strm_drop       : std_logic;
signal all_checker_err      : std_logic;
signal all_decoder_err      : std_logic;
signal any_checker_errs0    : std_logic;
signal hitmaker_dout_eos    : std_logic;
signal hitmaker_dout_ns     : std_logic;
signal hitmaker_dout_dv     : std_logic;


---------------------------------------------------------------
-- Delay
-------------------------------------------------------------
procedure clk_delay(
    constant nclks  : in  integer
) is
begin
    for I in 1 to nclks loop
        wait until clk'event and clk='0';
    end loop;
end;

----------------------------------------------------------------
-- Print a string with no time or instance path.
----------------------------------------------------------------
procedure cpu_print_msg(
    constant msg    : in    string
) is
variable line_out   : line;
begin
    write(line_out, msg);
    writeline(output, line_out);
end procedure cpu_print_msg;


begin
    
    -------------------------------------------------------------
    -- FPGA
    -------------------------------------------------------------
    u_fpga_KC705_enc_decode : entity work.fpga_KC705_enc_decode8
    port map(
        SYSCLK_P        => SYSCLK_P         , -- in  std_logic; 
        SYSCLK_N        => SYSCLK_N         , -- in  std_logic;
        CPU_RESET       => CPU_RESET        , -- in  std_logic; 
        GPIO_SW_N       => GPIO_SW_N        , -- in  std_logic; -- start
        GPIO_SW_S       => GPIO_SW_S        , -- in  std_logic; -- stop
        GPIO_SW_E       => GPIO_SW_E        , -- in  std_logic; -- 
        GPIO_SW_W       => GPIO_SW_W        , -- in  std_logic; -- 
        GPIO_SW_C       => GPIO_SW_C        , -- in  std_logic; -- 
        GPIO_DIP_SW0    => GPIO_DIP_SW0     , -- in  std_logic; -- for reg_hits_per_stream or reg_words_per_stream
        GPIO_DIP_SW1    => GPIO_DIP_SW1     , -- in  std_logic;
        GPIO_DIP_SW2    => GPIO_DIP_SW2     , -- in  std_logic;
        GPIO_DIP_SW3    => GPIO_DIP_SW3     , -- in  std_logic;
        GPIO_LED_0_LS   => GPIO_LED_0_LS    , -- out std_logic; 
        GPIO_LED_1_LS   => GPIO_LED_1_LS    , -- out std_logic;
        GPIO_LED_2_LS   => GPIO_LED_2_LS    , -- out std_logic;
        GPIO_LED_3_LS   => GPIO_LED_3_LS    , -- out std_logic;
        GPIO_LED_4_LS   => GPIO_LED_4_LS    , -- out std_logic;
        GPIO_LED_5_LS   => GPIO_LED_5_LS    , -- out std_logic;
        GPIO_LED_6_LS   => GPIO_LED_6_LS    , -- out std_logic;
        GPIO_LED_7_LS   => GPIO_LED_7_LS    , -- out std_logic;
        DEBUG_OUT       => DEBUG_OUT          -- out std_logic_vector( 6 downto 0)    
    );

    -- Debug pin mapping
    dist_strm_drop      <= DEBUG_OUT(0);
    all_checker_err     <= DEBUG_OUT(1);
    all_decoder_err     <= DEBUG_OUT(2);
    any_checker_errs0   <= DEBUG_OUT(3);
    hitmaker_dout_eos   <= DEBUG_OUT(4);
    hitmaker_dout_ns    <= DEBUG_OUT(5);
    hitmaker_dout_dv    <= DEBUG_OUT(6);

    -------------------------------------------------------------
    -- Generate logic clock
    -------------------------------------------------------------
    pr_clk : process
    begin
        clk  <= '0';
        wait for (CLK_PER_MHZ/2);
        clk  <= '1';
        wait for (CLK_PER_MHZ-CLK_PER_MHZ/2);
        if (sim_done=true) then
            wait;
        end if;
    end process;

    SYSCLK_P    <= clk;
    SYSCLK_N    <= not clk;

    reset       <= CPU_RESET;

    -------------------------------------------------------------
    -- Main 
    -------------------------------------------------------------
    pr_gen : process
    begin
        -- Reset
        CPU_RESET       <= '1';
        GPIO_SW_N       <= '0'; -- stop
        GPIO_SW_S       <= '0'; -- start
        clk_delay(10);
        CPU_RESET       <= '0';
        clk_delay(100);

        GPIO_SW_S       <= '1'; -- start
        clk_delay(20);
        GPIO_SW_S       <= '0';
        clk_delay(500000);
        wait;
        
        
        GPIO_SW_N       <= '1'; -- stop
        clk_delay(20);
        GPIO_SW_N       <= '0'; 
        clk_delay(1000);

        GPIO_SW_S       <= '1'; -- start
        clk_delay(20);
        GPIO_SW_S       <= '0';
        clk_delay(50000);
        sim_done        <= true;    -- Set sim_done to stop clock generation and bring simulation to a halt
        wait;

    end process;


end struct;

