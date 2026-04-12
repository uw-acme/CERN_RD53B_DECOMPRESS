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
# 00 : Orig, from decode8
# 01 Change LEDs/debug.  indiv checker errors from channel 0
# 02 Fix bug in decode_engine_2.  Shifting sreg when FIFO empty
# 03 Fix bug in dh_din selection when sreg does not have 30 bits remaining. Pad dh_din with zeros
# 04 Random hitmap from evgen.
# 05 Fix detection of X"0000" in random hitmap
#------------------------------------------------------------------------------
set_property BITSTREAM.CONFIG.USERID 32'hC7051105 [current_design]
#' Clock
#create_clock -period 5.000 -name SYSCLK_P -waveform {0.000 2.50} [get_ports SYSCLK_P]

set_property IOSTANDARD LVDS [get_ports SYSCLK_P]
set_property PACKAGE_PIN AD12 [get_ports SYSCLK_P]
set_property PACKAGE_PIN AD11 [get_ports SYSCLK_N]
set_property IOSTANDARD LVDS [get_ports SYSCLK_N]
# Must be FALSE for LVDS on a non-2.5V bank
set_property DIFF_TERM FALSE [get_ports SYSCLK_P]


# DIP Switches
set_property PACKAGE_PIN Y28 [get_ports GPIO_DIP_SW3]
set_property IOSTANDARD LVCMOS25 [get_ports GPIO_DIP_SW3]
set_property PACKAGE_PIN AA28 [get_ports GPIO_DIP_SW2]
set_property IOSTANDARD LVCMOS25 [get_ports GPIO_DIP_SW2]
set_property PACKAGE_PIN W29 [get_ports GPIO_DIP_SW1]
set_property IOSTANDARD LVCMOS25 [get_ports GPIO_DIP_SW1]
set_property PACKAGE_PIN Y29 [get_ports GPIO_DIP_SW0]
set_property IOSTANDARD LVCMOS25 [get_ports GPIO_DIP_SW0]

# Reset button
set_property PACKAGE_PIN AB7 [get_ports CPU_RESET]
set_property IOSTANDARD LVCMOS15 [get_ports CPU_RESET]

set_property PACKAGE_PIN AA12 [get_ports GPIO_SW_N]
set_property IOSTANDARD LVCMOS15 [get_ports GPIO_SW_N]
set_property PACKAGE_PIN AB12 [get_ports GPIO_SW_S]
set_property IOSTANDARD LVCMOS15 [get_ports GPIO_SW_S]

#set_property PACKAGE_PIN AG5     [get_ports GPIO_SW_E]
#set_property IOSTANDARD LVCMOS15 [get_ports GPIO_SW_E]
#set_property PACKAGE_PIN AC12    [get_ports GPIO_SW_W]
#set_property IOSTANDARD LVCMOS15 [get_ports GPIO_SW_W]

#set_property PACKAGE_PIN G12     [get_ports GPIO_SW_C]
#set_property IOSTANDARD LVCMOS25 [get_ports GPIO_SW_C]

## LVCMOS25
set_property PACKAGE_PIN F16 [get_ports GPIO_LED_7_LS]
set_property IOSTANDARD LVCMOS25 [get_ports GPIO_LED_7_LS]
set_property PACKAGE_PIN E18 [get_ports GPIO_LED_6_LS]
set_property IOSTANDARD LVCMOS25 [get_ports GPIO_LED_6_LS]
set_property PACKAGE_PIN G19 [get_ports GPIO_LED_5_LS]
set_property IOSTANDARD LVCMOS25 [get_ports GPIO_LED_5_LS]
set_property PACKAGE_PIN AE26 [get_ports GPIO_LED_4_LS]
set_property IOSTANDARD LVCMOS25 [get_ports GPIO_LED_4_LS]
## LVCMOS15
set_property PACKAGE_PIN AB9 [get_ports GPIO_LED_3_LS]
set_property IOSTANDARD LVCMOS15 [get_ports GPIO_LED_3_LS]
set_property PACKAGE_PIN AC9 [get_ports GPIO_LED_2_LS]
set_property IOSTANDARD LVCMOS15 [get_ports GPIO_LED_2_LS]
set_property PACKAGE_PIN AA8 [get_ports GPIO_LED_1_LS]
set_property IOSTANDARD LVCMOS15 [get_ports GPIO_LED_1_LS]
set_property PACKAGE_PIN AB8 [get_ports GPIO_LED_0_LS]
set_property IOSTANDARD LVCMOS15 [get_ports GPIO_LED_0_LS]


set_property PACKAGE_PIN AA13 [get_ports {DEBUG_OUT[0]}]
set_property IOSTANDARD LVCMOS15 [get_ports {DEBUG_OUT[0]}]
set_property PACKAGE_PIN AA10 [get_ports {DEBUG_OUT[1]}]
set_property IOSTANDARD LVCMOS15 [get_ports {DEBUG_OUT[1]}]
set_property PACKAGE_PIN AA11 [get_ports {DEBUG_OUT[2]}]
set_property IOSTANDARD LVCMOS15 [get_ports {DEBUG_OUT[2]}]
set_property PACKAGE_PIN Y10 [get_ports {DEBUG_OUT[3]}]
set_property IOSTANDARD LVCMOS15 [get_ports {DEBUG_OUT[3]}]
set_property PACKAGE_PIN AB13 [get_ports {DEBUG_OUT[4]}]
set_property IOSTANDARD LVCMOS15 [get_ports {DEBUG_OUT[4]}]
set_property PACKAGE_PIN Y11 [get_ports {DEBUG_OUT[5]}]
set_property IOSTANDARD LVCMOS15 [get_ports {DEBUG_OUT[5]}]
set_property PACKAGE_PIN AB10 [get_ports {DEBUG_OUT[6]}]
set_property IOSTANDARD LVCMOS15 [get_ports {DEBUG_OUT[6]}]
#set_property PACKAGE_PIN AB10    [get_ports DEBUG_OUT[7]]
#set_property IOSTANDARD LVCMOS15 [get_ports DEBUG_OUT[7]]
#set_property PACKAGE_PIN AB10    [get_ports DEBUG_OUT[8]]
#set_property IOSTANDARD LVCMOS15 [get_ports DEBUG_OUT[8]]
#set_property PACKAGE_PIN AB10    [get_ports DEBUG_OUT[9]]
#set_property IOSTANDARD LVCMOS15 [get_ports DEBUG_OUT[9]]




connect_debug_port u_ila_0/probe0 [get_nets [list {checker0_errs[0]} {checker0_errs[1]} {checker0_errs[2]} {checker0_errs[3]} {checker0_errs[4]} {checker0_errs[5]} {checker0_errs[6]} {checker0_errs[7]}]]
connect_debug_port u_ila_0/probe6 [get_nets [list {u_decode/dout_ccol[0]} {u_decode/dout_ccol[1]} {u_decode/dout_ccol[2]} {u_decode/dout_ccol[3]} {u_decode/dout_ccol[4]} {u_decode/dout_ccol[5]}]]
connect_debug_port u_ila_0/probe7 [get_nets [list {u_decode/dout_hitmap[0]} {u_decode/dout_hitmap[1]} {u_decode/dout_hitmap[2]} {u_decode/dout_hitmap[3]} {u_decode/dout_hitmap[4]} {u_decode/dout_hitmap[5]} {u_decode/dout_hitmap[6]} {u_decode/dout_hitmap[7]} {u_decode/dout_hitmap[8]} {u_decode/dout_hitmap[9]} {u_decode/dout_hitmap[10]} {u_decode/dout_hitmap[11]} {u_decode/dout_hitmap[12]} {u_decode/dout_hitmap[13]} {u_decode/dout_hitmap[14]} {u_decode/dout_hitmap[15]}]]
connect_debug_port u_ila_0/probe8 [get_nets [list {u_decode/dout_tot[0]} {u_decode/dout_tot[1]} {u_decode/dout_tot[2]} {u_decode/dout_tot[3]} {u_decode/dout_tot[4]} {u_decode/dout_tot[5]} {u_decode/dout_tot[6]} {u_decode/dout_tot[7]} {u_decode/dout_tot[8]} {u_decode/dout_tot[9]} {u_decode/dout_tot[10]} {u_decode/dout_tot[11]} {u_decode/dout_tot[12]} {u_decode/dout_tot[13]} {u_decode/dout_tot[14]} {u_decode/dout_tot[15]} {u_decode/dout_tot[16]} {u_decode/dout_tot[17]} {u_decode/dout_tot[18]} {u_decode/dout_tot[19]} {u_decode/dout_tot[20]} {u_decode/dout_tot[21]} {u_decode/dout_tot[22]} {u_decode/dout_tot[23]} {u_decode/dout_tot[24]} {u_decode/dout_tot[25]} {u_decode/dout_tot[26]} {u_decode/dout_tot[27]} {u_decode/dout_tot[28]} {u_decode/dout_tot[29]} {u_decode/dout_tot[30]} {u_decode/dout_tot[31]} {u_decode/dout_tot[32]} {u_decode/dout_tot[33]} {u_decode/dout_tot[34]} {u_decode/dout_tot[35]} {u_decode/dout_tot[36]} {u_decode/dout_tot[37]} {u_decode/dout_tot[38]} {u_decode/dout_tot[39]} {u_decode/dout_tot[40]} {u_decode/dout_tot[41]} {u_decode/dout_tot[42]} {u_decode/dout_tot[43]} {u_decode/dout_tot[44]} {u_decode/dout_tot[45]} {u_decode/dout_tot[46]} {u_decode/dout_tot[47]} {u_decode/dout_tot[48]} {u_decode/dout_tot[49]} {u_decode/dout_tot[50]} {u_decode/dout_tot[51]} {u_decode/dout_tot[52]} {u_decode/dout_tot[53]} {u_decode/dout_tot[54]} {u_decode/dout_tot[55]} {u_decode/dout_tot[56]} {u_decode/dout_tot[57]} {u_decode/dout_tot[58]} {u_decode/dout_tot[59]} {u_decode/dout_tot[60]} {u_decode/dout_tot[61]} {u_decode/dout_tot[62]} {u_decode/dout_tot[63]}]]
connect_debug_port u_ila_0/probe9 [get_nets [list {u_decode/dout_qrow[0]} {u_decode/dout_qrow[1]} {u_decode/dout_qrow[2]} {u_decode/dout_qrow[3]} {u_decode/dout_qrow[4]} {u_decode/dout_qrow[5]} {u_decode/dout_qrow[6]} {u_decode/dout_qrow[7]}]]
connect_debug_port u_ila_0/probe10 [get_nets [list {u_decode/din[0]} {u_decode/din[1]} {u_decode/din[2]} {u_decode/din[3]} {u_decode/din[4]} {u_decode/din[5]} {u_decode/din[6]} {u_decode/din[7]} {u_decode/din[8]} {u_decode/din[9]} {u_decode/din[10]} {u_decode/din[11]} {u_decode/din[12]} {u_decode/din[13]} {u_decode/din[14]} {u_decode/din[15]} {u_decode/din[16]} {u_decode/din[17]} {u_decode/din[18]} {u_decode/din[19]} {u_decode/din[20]} {u_decode/din[21]} {u_decode/din[22]} {u_decode/din[23]} {u_decode/din[24]} {u_decode/din[25]} {u_decode/din[26]} {u_decode/din[27]} {u_decode/din[28]} {u_decode/din[29]} {u_decode/din[30]} {u_decode/din[31]} {u_decode/din[32]} {u_decode/din[33]} {u_decode/din[34]} {u_decode/din[35]} {u_decode/din[36]} {u_decode/din[37]} {u_decode/din[38]} {u_decode/din[39]} {u_decode/din[40]} {u_decode/din[41]} {u_decode/din[42]} {u_decode/din[43]} {u_decode/din[44]} {u_decode/din[45]} {u_decode/din[46]} {u_decode/din[47]} {u_decode/din[48]} {u_decode/din[49]} {u_decode/din[50]} {u_decode/din[51]} {u_decode/din[52]} {u_decode/din[53]} {u_decode/din[54]} {u_decode/din[55]} {u_decode/din[56]} {u_decode/din[57]} {u_decode/din[58]} {u_decode/din[59]} {u_decode/din[60]} {u_decode/din[61]} {u_decode/din[62]}]]
connect_debug_port u_ila_0/probe11 [get_nets [list {u_decode/state[0]} {u_decode/state[1]} {u_decode/state[2]} {u_decode/state[3]}]]
connect_debug_port u_ila_0/probe12 [get_nets [list u_decode/din_dv]]
connect_debug_port u_ila_0/probe13 [get_nets [list u_decode/din_ns]]
connect_debug_port u_ila_0/probe14 [get_nets [list u_decode/dout_dv]]
connect_debug_port u_ila_0/probe15 [get_nets [list u_decode/dout_eos]]
connect_debug_port u_ila_0/probe17 [get_nets [list exp_hit_eoe]]
connect_debug_port u_ila_0/probe20 [get_nets [list exp_hit_tot_eos]]
connect_debug_port u_ila_0/probe21 [get_nets [list u_decode/is_last]]
connect_debug_port u_ila_0/probe22 [get_nets [list u_decode/is_neighbor]]
connect_debug_port u_ila_0/probe23 [get_nets [list u_decode/sm_rd_fifo]]
connect_debug_port u_ila_0/probe24 [get_nets [list u_decode/start_sm]]



connect_debug_port u_ila_0/probe0 [get_nets [list {u_decode/dout_qrow[0]} {u_decode/dout_qrow[1]} {u_decode/dout_qrow[2]} {u_decode/dout_qrow[3]} {u_decode/dout_qrow[4]} {u_decode/dout_qrow[5]} {u_decode/dout_qrow[6]} {u_decode/dout_qrow[7]}]]
connect_debug_port u_ila_0/probe1 [get_nets [list {u_decode/din[0]} {u_decode/din[1]} {u_decode/din[2]} {u_decode/din[3]} {u_decode/din[4]} {u_decode/din[5]} {u_decode/din[6]} {u_decode/din[7]} {u_decode/din[8]} {u_decode/din[9]} {u_decode/din[10]} {u_decode/din[11]} {u_decode/din[12]} {u_decode/din[13]} {u_decode/din[14]} {u_decode/din[15]} {u_decode/din[16]} {u_decode/din[17]} {u_decode/din[18]} {u_decode/din[19]} {u_decode/din[20]} {u_decode/din[21]} {u_decode/din[22]} {u_decode/din[23]} {u_decode/din[24]} {u_decode/din[25]} {u_decode/din[26]} {u_decode/din[27]} {u_decode/din[28]} {u_decode/din[29]} {u_decode/din[30]} {u_decode/din[31]} {u_decode/din[32]} {u_decode/din[33]} {u_decode/din[34]} {u_decode/din[35]} {u_decode/din[36]} {u_decode/din[37]} {u_decode/din[38]} {u_decode/din[39]} {u_decode/din[40]} {u_decode/din[41]} {u_decode/din[42]} {u_decode/din[43]} {u_decode/din[44]} {u_decode/din[45]} {u_decode/din[46]} {u_decode/din[47]} {u_decode/din[48]} {u_decode/din[49]} {u_decode/din[50]} {u_decode/din[51]} {u_decode/din[52]} {u_decode/din[53]} {u_decode/din[54]} {u_decode/din[55]} {u_decode/din[56]} {u_decode/din[57]} {u_decode/din[58]} {u_decode/din[59]} {u_decode/din[60]} {u_decode/din[61]} {u_decode/din[62]}]]
connect_debug_port u_ila_0/probe2 [get_nets [list {u_decode/din_chan[0]} {u_decode/din_chan[1]} {u_decode/din_chan[2]}]]
connect_debug_port u_ila_0/probe3 [get_nets [list {u_decode/dout_ccol[0]} {u_decode/dout_ccol[1]} {u_decode/dout_ccol[2]} {u_decode/dout_ccol[3]} {u_decode/dout_ccol[4]} {u_decode/dout_ccol[5]}]]
connect_debug_port u_ila_0/probe4 [get_nets [list {u_decode/dout_hitmap[0]} {u_decode/dout_hitmap[1]} {u_decode/dout_hitmap[2]} {u_decode/dout_hitmap[3]} {u_decode/dout_hitmap[4]} {u_decode/dout_hitmap[5]} {u_decode/dout_hitmap[6]} {u_decode/dout_hitmap[7]} {u_decode/dout_hitmap[8]} {u_decode/dout_hitmap[9]} {u_decode/dout_hitmap[10]} {u_decode/dout_hitmap[11]} {u_decode/dout_hitmap[12]} {u_decode/dout_hitmap[13]} {u_decode/dout_hitmap[14]} {u_decode/dout_hitmap[15]}]]
connect_debug_port u_ila_0/probe5 [get_nets [list {u_decode/dout_tot[0]} {u_decode/dout_tot[1]} {u_decode/dout_tot[2]} {u_decode/dout_tot[3]} {u_decode/dout_tot[4]} {u_decode/dout_tot[5]} {u_decode/dout_tot[6]} {u_decode/dout_tot[7]} {u_decode/dout_tot[8]} {u_decode/dout_tot[9]} {u_decode/dout_tot[10]} {u_decode/dout_tot[11]} {u_decode/dout_tot[12]} {u_decode/dout_tot[13]} {u_decode/dout_tot[14]} {u_decode/dout_tot[15]} {u_decode/dout_tot[16]} {u_decode/dout_tot[17]} {u_decode/dout_tot[18]} {u_decode/dout_tot[19]} {u_decode/dout_tot[20]} {u_decode/dout_tot[21]} {u_decode/dout_tot[22]} {u_decode/dout_tot[23]} {u_decode/dout_tot[24]} {u_decode/dout_tot[25]} {u_decode/dout_tot[26]} {u_decode/dout_tot[27]} {u_decode/dout_tot[28]} {u_decode/dout_tot[29]} {u_decode/dout_tot[30]} {u_decode/dout_tot[31]} {u_decode/dout_tot[32]} {u_decode/dout_tot[33]} {u_decode/dout_tot[34]} {u_decode/dout_tot[35]} {u_decode/dout_tot[36]} {u_decode/dout_tot[37]} {u_decode/dout_tot[38]} {u_decode/dout_tot[39]} {u_decode/dout_tot[40]} {u_decode/dout_tot[41]} {u_decode/dout_tot[42]} {u_decode/dout_tot[43]} {u_decode/dout_tot[44]} {u_decode/dout_tot[45]} {u_decode/dout_tot[46]} {u_decode/dout_tot[47]} {u_decode/dout_tot[48]} {u_decode/dout_tot[49]} {u_decode/dout_tot[50]} {u_decode/dout_tot[51]} {u_decode/dout_tot[52]} {u_decode/dout_tot[53]} {u_decode/dout_tot[54]} {u_decode/dout_tot[55]} {u_decode/dout_tot[56]} {u_decode/dout_tot[57]} {u_decode/dout_tot[58]} {u_decode/dout_tot[59]} {u_decode/dout_tot[60]} {u_decode/dout_tot[61]} {u_decode/dout_tot[62]} {u_decode/dout_tot[63]}]]
connect_debug_port u_ila_0/probe6 [get_nets [list {u_decode/state[0]} {u_decode/state[1]} {u_decode/state[2]} {u_decode/state[3]}]]
connect_debug_port u_ila_0/probe8 [get_nets [list {checker0_errs[0]} {checker0_errs[1]} {checker0_errs[2]} {checker0_errs[3]} {checker0_errs[4]} {checker0_errs[5]} {checker0_errs[6]} {checker0_errs[7]}]]
connect_debug_port u_ila_0/probe13 [get_nets [list u_decode/din_dv]]
connect_debug_port u_ila_0/probe14 [get_nets [list u_decode/din_ns]]
connect_debug_port u_ila_0/probe15 [get_nets [list u_decode/dout_dv]]
connect_debug_port u_ila_0/probe19 [get_nets [list exp_hit_tot_eos]]
connect_debug_port u_ila_0/probe20 [get_nets [list u_decode/is_last]]
connect_debug_port u_ila_0/probe21 [get_nets [list u_decode/is_neighbor]]
connect_debug_port u_ila_0/probe22 [get_nets [list u_decode/sm_rd_fifo]]
connect_debug_port u_ila_0/probe23 [get_nets [list u_decode/start_sm]]
connect_debug_port u_ila_0/probe24 [get_nets [list u_decode/dout_eos]]

