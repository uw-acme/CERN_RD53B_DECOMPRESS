#------------------------------------------------------------------------------
#
# Constraint file for Decoder test a xc7k325 on Xilinx KC705 dev board
#
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Version number for bitfile that can be seen at the top of the 'bit' file and
# can be read by the Hardware Manager
# 'C705' = KC705
#------------------------------------------------------------------------------
# "01xx" No CPU
# "02xx" MicroBlaze CPU
#------------------------------------------------------------------------------
# 00 : Orig
# 01 Change LEDs. Remove lock, tick_sec. More checker errors
# 02 Add 'reg_words_per_stream' instead of hits_per_stream controlled by DIP switches
# 03 Change debug outputs
# 04 Add decoder errors to LEDs and debug.  Prevent writes when decoder FIFO > 500
# 05 Fix cnt_words_per_stream
# 06 Fix event generator to go to S_END_OF_STREAM at max hitmap instead of S_WR_IDLE. Avoid too short gap.
# 07 Fix event gen to not EOS when hitmap wraps around
# 08 Fix event gen to not generate hitmap all zero
# 09 Fix decode_engine bug when less than 30 bits in sreg for hitmap decode
# 0A Random hitmaps
#------------------------------------------------------------------------------
#' Clock
#create_clock -period 5.000 -name SYSCLK_P -waveform {0.000 2.50} [get_ports SYSCLK_P]

# Must be FALSE for LVDS on a non-2.5V bank
set_property DIFF_TERM FALSE [get_ports SYSCLK_N]


# DIP Switches

# Reset button


#set_property PACKAGE_PIN AG5     [get_ports GPIO_SW_E]
#set_property IOSTANDARD LVCMOS15 [get_ports GPIO_SW_E]
#set_property PACKAGE_PIN AC12    [get_ports GPIO_SW_W]
#set_property IOSTANDARD LVCMOS15 [get_ports GPIO_SW_W]

#set_property PACKAGE_PIN G12     [get_ports GPIO_SW_C]
#set_property IOSTANDARD LVCMOS25 [get_ports GPIO_SW_C]

## LVCMOS25
## LVCMOS15


#set_property PACKAGE_PIN AB10    [get_ports DEBUG_OUT[7]]
#set_property IOSTANDARD LVCMOS15 [get_ports DEBUG_OUT[7]]
#set_property PACKAGE_PIN AB10    [get_ports DEBUG_OUT[8]]
#set_property IOSTANDARD LVCMOS15 [get_ports DEBUG_OUT[8]]
#set_property PACKAGE_PIN AB10    [get_ports DEBUG_OUT[9]]
#set_property IOSTANDARD LVCMOS15 [get_ports DEBUG_OUT[9]]


connect_debug_port u_ila_0/probe0 [get_nets [list {arr_checker_errs[5][0]} {arr_checker_errs[5][1]} {arr_checker_errs[5][2]} {arr_checker_errs[5][3]} {arr_checker_errs[5][4]} {arr_checker_errs[5][5]} {arr_checker_errs[5][6]} {arr_checker_errs[5][7]}]]
connect_debug_port u_ila_0/probe1 [get_nets [list {arr_checker_errs[7][0]} {arr_checker_errs[7][1]} {arr_checker_errs[7][2]} {arr_checker_errs[7][3]} {arr_checker_errs[7][4]} {arr_checker_errs[7][5]} {arr_checker_errs[7][6]} {arr_checker_errs[7][7]}]]
connect_debug_port u_ila_0/probe3 [get_nets [list {arr_checker_errs[0][0]} {arr_checker_errs[0][1]} {arr_checker_errs[0][2]} {arr_checker_errs[0][3]} {arr_checker_errs[0][4]} {arr_checker_errs[0][5]} {arr_checker_errs[0][6]} {arr_checker_errs[0][7]}]]
connect_debug_port u_ila_0/probe4 [get_nets [list {arr_checker_errs[3][0]} {arr_checker_errs[3][1]} {arr_checker_errs[3][2]} {arr_checker_errs[3][3]} {arr_checker_errs[3][4]} {arr_checker_errs[3][5]} {arr_checker_errs[3][6]} {arr_checker_errs[3][7]}]]
connect_debug_port u_ila_0/probe5 [get_nets [list {arr_checker_errs[1][0]} {arr_checker_errs[1][1]} {arr_checker_errs[1][2]} {arr_checker_errs[1][3]} {arr_checker_errs[1][4]} {arr_checker_errs[1][5]} {arr_checker_errs[1][6]} {arr_checker_errs[1][7]}]]
connect_debug_port u_ila_0/probe6 [get_nets [list {arr_checker_errs[2][0]} {arr_checker_errs[2][1]} {arr_checker_errs[2][2]} {arr_checker_errs[2][3]} {arr_checker_errs[2][4]} {arr_checker_errs[2][5]} {arr_checker_errs[2][6]} {arr_checker_errs[2][7]}]]
connect_debug_port u_ila_0/probe7 [get_nets [list {arr_checker_errs[6][0]} {arr_checker_errs[6][1]} {arr_checker_errs[6][2]} {arr_checker_errs[6][3]} {arr_checker_errs[6][4]} {arr_checker_errs[6][5]} {arr_checker_errs[6][6]} {arr_checker_errs[6][7]}]]
connect_debug_port u_ila_0/probe8 [get_nets [list {arr_checker_errs[4][0]} {arr_checker_errs[4][1]} {arr_checker_errs[4][2]} {arr_checker_errs[4][3]} {arr_checker_errs[4][4]} {arr_checker_errs[4][5]} {arr_checker_errs[4][6]} {arr_checker_errs[4][7]}]]

create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 2 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list u_clkreset/u_clkgen160/inst/clk_out1]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 8 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {any_checker_errs[0]} {any_checker_errs[1]} {any_checker_errs[2]} {any_checker_errs[3]} {any_checker_errs[4]} {any_checker_errs[5]} {any_checker_errs[6]} {any_checker_errs[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 8 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {decoders_busy[0]} {decoders_busy[1]} {decoders_busy[2]} {decoders_busy[3]} {decoders_busy[4]} {decoders_busy[5]} {decoders_busy[6]} {decoders_busy[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 8 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {dist_strm_dout_dvs[0]} {dist_strm_dout_dvs[1]} {dist_strm_dout_dvs[2]} {dist_strm_dout_dvs[3]} {dist_strm_dout_dvs[4]} {dist_strm_dout_dvs[5]} {dist_strm_dout_dvs[6]} {dist_strm_dout_dvs[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 16 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list {exp_hit_hitmap[0]} {exp_hit_hitmap[1]} {exp_hit_hitmap[2]} {exp_hit_hitmap[3]} {exp_hit_hitmap[4]} {exp_hit_hitmap[5]} {exp_hit_hitmap[6]} {exp_hit_hitmap[7]} {exp_hit_hitmap[8]} {exp_hit_hitmap[9]} {exp_hit_hitmap[10]} {exp_hit_hitmap[11]} {exp_hit_hitmap[12]} {exp_hit_hitmap[13]} {exp_hit_hitmap[14]} {exp_hit_hitmap[15]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 64 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list {exp_hit_tot[0]} {exp_hit_tot[1]} {exp_hit_tot[2]} {exp_hit_tot[3]} {exp_hit_tot[4]} {exp_hit_tot[5]} {exp_hit_tot[6]} {exp_hit_tot[7]} {exp_hit_tot[8]} {exp_hit_tot[9]} {exp_hit_tot[10]} {exp_hit_tot[11]} {exp_hit_tot[12]} {exp_hit_tot[13]} {exp_hit_tot[14]} {exp_hit_tot[15]} {exp_hit_tot[16]} {exp_hit_tot[17]} {exp_hit_tot[18]} {exp_hit_tot[19]} {exp_hit_tot[20]} {exp_hit_tot[21]} {exp_hit_tot[22]} {exp_hit_tot[23]} {exp_hit_tot[24]} {exp_hit_tot[25]} {exp_hit_tot[26]} {exp_hit_tot[27]} {exp_hit_tot[28]} {exp_hit_tot[29]} {exp_hit_tot[30]} {exp_hit_tot[31]} {exp_hit_tot[32]} {exp_hit_tot[33]} {exp_hit_tot[34]} {exp_hit_tot[35]} {exp_hit_tot[36]} {exp_hit_tot[37]} {exp_hit_tot[38]} {exp_hit_tot[39]} {exp_hit_tot[40]} {exp_hit_tot[41]} {exp_hit_tot[42]} {exp_hit_tot[43]} {exp_hit_tot[44]} {exp_hit_tot[45]} {exp_hit_tot[46]} {exp_hit_tot[47]} {exp_hit_tot[48]} {exp_hit_tot[49]} {exp_hit_tot[50]} {exp_hit_tot[51]} {exp_hit_tot[52]} {exp_hit_tot[53]} {exp_hit_tot[54]} {exp_hit_tot[55]} {exp_hit_tot[56]} {exp_hit_tot[57]} {exp_hit_tot[58]} {exp_hit_tot[59]} {exp_hit_tot[60]} {exp_hit_tot[61]} {exp_hit_tot[62]} {exp_hit_tot[63]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 6 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list {exp_hit_ccol[0]} {exp_hit_ccol[1]} {exp_hit_ccol[2]} {exp_hit_ccol[3]} {exp_hit_ccol[4]} {exp_hit_ccol[5]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe6]
set_property port_width 63 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets [list {dist_strm_dout[0]} {dist_strm_dout[1]} {dist_strm_dout[2]} {dist_strm_dout[3]} {dist_strm_dout[4]} {dist_strm_dout[5]} {dist_strm_dout[6]} {dist_strm_dout[7]} {dist_strm_dout[8]} {dist_strm_dout[9]} {dist_strm_dout[10]} {dist_strm_dout[11]} {dist_strm_dout[12]} {dist_strm_dout[13]} {dist_strm_dout[14]} {dist_strm_dout[15]} {dist_strm_dout[16]} {dist_strm_dout[17]} {dist_strm_dout[18]} {dist_strm_dout[19]} {dist_strm_dout[20]} {dist_strm_dout[21]} {dist_strm_dout[22]} {dist_strm_dout[23]} {dist_strm_dout[24]} {dist_strm_dout[25]} {dist_strm_dout[26]} {dist_strm_dout[27]} {dist_strm_dout[28]} {dist_strm_dout[29]} {dist_strm_dout[30]} {dist_strm_dout[31]} {dist_strm_dout[32]} {dist_strm_dout[33]} {dist_strm_dout[34]} {dist_strm_dout[35]} {dist_strm_dout[36]} {dist_strm_dout[37]} {dist_strm_dout[38]} {dist_strm_dout[39]} {dist_strm_dout[40]} {dist_strm_dout[41]} {dist_strm_dout[42]} {dist_strm_dout[43]} {dist_strm_dout[44]} {dist_strm_dout[45]} {dist_strm_dout[46]} {dist_strm_dout[47]} {dist_strm_dout[48]} {dist_strm_dout[49]} {dist_strm_dout[50]} {dist_strm_dout[51]} {dist_strm_dout[52]} {dist_strm_dout[53]} {dist_strm_dout[54]} {dist_strm_dout[55]} {dist_strm_dout[56]} {dist_strm_dout[57]} {dist_strm_dout[58]} {dist_strm_dout[59]} {dist_strm_dout[60]} {dist_strm_dout[61]} {dist_strm_dout[62]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe7]
set_property port_width 8 [get_debug_ports u_ila_0/probe7]
connect_debug_port u_ila_0/probe7 [get_nets [list {exp_hit_qrow[0]} {exp_hit_qrow[1]} {exp_hit_qrow[2]} {exp_hit_qrow[3]} {exp_hit_qrow[4]} {exp_hit_qrow[5]} {exp_hit_qrow[6]} {exp_hit_qrow[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe8]
set_property port_width 7 [get_debug_ports u_ila_0/probe8]
connect_debug_port u_ila_0/probe8 [get_nets [list {exp_hit_tot_size[0]} {exp_hit_tot_size[1]} {exp_hit_tot_size[2]} {exp_hit_tot_size[3]} {exp_hit_tot_size[4]} {exp_hit_tot_size[5]} {exp_hit_tot_size[6]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe9]
set_property port_width 1 [get_debug_ports u_ila_0/probe9]
connect_debug_port u_ila_0/probe9 [get_nets [list dist_strm_dout_ns]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe10]
set_property port_width 1 [get_debug_ports u_ila_0/probe10]
connect_debug_port u_ila_0/probe10 [get_nets [list dist_strm_drop]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe11]
set_property port_width 1 [get_debug_ports u_ila_0/probe11]
connect_debug_port u_ila_0/probe11 [get_nets [list exp_hit_dv]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe12]
set_property port_width 1 [get_debug_ports u_ila_0/probe12]
connect_debug_port u_ila_0/probe12 [get_nets [list exp_hit_eoe]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe13]
set_property port_width 1 [get_debug_ports u_ila_0/probe13]
connect_debug_port u_ila_0/probe13 [get_nets [list exp_hit_eos]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe14]
set_property port_width 1 [get_debug_ports u_ila_0/probe14]
connect_debug_port u_ila_0/probe14 [get_nets [list exp_hit_tot_dv]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe15]
set_property port_width 1 [get_debug_ports u_ila_0/probe15]
connect_debug_port u_ila_0/probe15 [get_nets [list exp_hit_tot_eos]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk]
