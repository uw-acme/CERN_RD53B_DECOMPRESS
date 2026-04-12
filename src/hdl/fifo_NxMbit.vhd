----------------------------------------------------------------------------
-- FIFO : Common clock, Fall-through, full, empty, level outputs
----------------------------------------------------------------------------
library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity fifo_NxMbit is
generic (
    G_DEPTH     : integer := 16;    -- Depth of FIFO
    G_WIDTH     : integer := 16     -- Bitwidth of FIFO
); 
port (    
    reset       : in  std_logic;
    clk         : in  std_logic;

    wr          : in  std_logic;                            -- Write
    data_in     : in  std_logic_vector(G_WIDTH-1 downto 0); -- Input data

    rd          : in  std_logic;                            -- Read
    data_out    : out std_logic_vector(G_WIDTH-1 downto 0); -- Output data

    level       : out std_logic_vector( 9 downto 0);        -- Number of words stored in FIFO
    empty       : out std_logic;                            -- Set as '1' when the FIFO is empty
    full        : out std_logic                             -- Set as '1' when the FIFO is full
);
end fifo_NxMbit;

architecture behavioral of fifo_NxMbit is

type   t_memory is array (0 to G_DEPTH-1) of std_logic_vector(G_WIDTH-1 downto 0);
signal memory           : t_memory  := (others=>(others=>'0'));   -- FIFO data storage array

signal ptr_read         : integer   :=  0;      -- Read pointer.
signal ptr_write        : integer   :=  0;      -- Write pointer.
signal empty_i          : std_logic := '0';
signal full_i           : std_logic := '0';
signal data_count       : unsigned(9 downto 0); 

begin

    empty       <= empty_i;
    full        <= full_i;
    level       <= std_logic_vector(data_count);

    -- First word fall-through
    data_out    <= memory(ptr_read);

    ------------------------------------------------------------------------
    -- All logic in one process
    ------------------------------------------------------------------------
    pr_fifo : process (reset, clk)

    variable v_num_elem : integer := 0;  -- Number of elements stored in fifo.  Used to decide whether the fifo is empty or full.

    begin

        if (reset = '1') then

            empty_i     <= '1';
            full_i      <= '0';
            ptr_read    <= 0;
            ptr_write   <= 0;
            v_num_elem  := 0;
            data_count  <= (others=>'0');

        elsif (rising_edge(clk)) then

            -- Read
            if (rd = '1' and empty_i = '0') then
                ptr_read            <= ptr_read + 1;      
                v_num_elem          := v_num_elem - 1;
            end if;

            -- Write
            if (wr ='1' and full_i = '0') then
                memory(ptr_write)   <= data_in;
                ptr_write           <= ptr_write + 1;  
                v_num_elem          := v_num_elem + 1;
            end if;

            -- Wrap indices.
            if (ptr_read = G_DEPTH-1 and rd = '1') then      -- Wrap read pointer.
                ptr_read    <= 0;
            end if;

            if (ptr_write = G_DEPTH-1 and wr = '1') then     -- Wrap write pointer.
                ptr_write   <= 0;
            end if; 

            -- Set empty and full flags.
            if (v_num_elem = 0) then
                empty_i <= '1';
            else
                empty_i <= '0';
            end if;

            if (v_num_elem = G_DEPTH) then
                full_i  <= '1';
            else
                full_i  <= '0';
            end if;

            data_count  <= to_unsigned(v_num_elem,10);

        end if; 

    end process;

end behavioral;

