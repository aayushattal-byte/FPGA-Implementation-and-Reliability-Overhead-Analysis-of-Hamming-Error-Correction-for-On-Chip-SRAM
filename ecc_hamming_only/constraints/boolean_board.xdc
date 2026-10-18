## ============================================================================
## boolean_board.xdc
## Constraints for the RealDigital Boolean Board (Xilinx Spartan-7,
## part xc7s50csga324-1).
##
## Pin numbers below are taken directly from RealDigital's own official
## documentation ("Creating a Vivado Project for the Boolean Board"),
## https://www.realdigital.org/doc/c4ceeb20d229e5f3d4e32f3a74e343e9
## -- not guessed/templated. If you're on a different board despite the
## same part number, re-check against your board's own reference doc.
##
## Signal names below match top_ecc_demo.v's port list exactly:
##   clk100, btn_step, btn_inject, btn_clear, sw_bitpos[6:0],
##   led_pass, led_sec, led_ded, led_heartbeat
## ============================================================================

## ---- 100 MHz system oscillator (board calls this "mclk") ----
set_property -dict { PACKAGE_PIN F14 IOSTANDARD LVCMOS33 } [get_ports { clk100 }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk100 }];

## ---- push buttons (board has 4: btn[0]-btn[3], we use 3) ----
set_property -dict { PACKAGE_PIN J2 IOSTANDARD LVCMOS33 } [get_ports { btn_step   }]; # btn[0]
set_property -dict { PACKAGE_PIN J5 IOSTANDARD LVCMOS33 } [get_ports { btn_inject }]; # btn[1]
set_property -dict { PACKAGE_PIN H2 IOSTANDARD LVCMOS33 } [get_ports { btn_clear  }]; # btn[2]
## btn[3] is on pin J1, unused by this design

## ---- switches (board has 16: sw[0]-sw[15], we use 7 for bit position 0..71) ----
set_property -dict { PACKAGE_PIN V2 IOSTANDARD LVCMOS33 } [get_ports { sw_bitpos[0] }]; # sw[0]
set_property -dict { PACKAGE_PIN U2 IOSTANDARD LVCMOS33 } [get_ports { sw_bitpos[1] }]; # sw[1]
set_property -dict { PACKAGE_PIN U1 IOSTANDARD LVCMOS33 } [get_ports { sw_bitpos[2] }]; # sw[2]
set_property -dict { PACKAGE_PIN T2 IOSTANDARD LVCMOS33 } [get_ports { sw_bitpos[3] }]; # sw[3]
set_property -dict { PACKAGE_PIN T1 IOSTANDARD LVCMOS33 } [get_ports { sw_bitpos[4] }]; # sw[4]
set_property -dict { PACKAGE_PIN R2 IOSTANDARD LVCMOS33 } [get_ports { sw_bitpos[5] }]; # sw[5]
set_property -dict { PACKAGE_PIN R1 IOSTANDARD LVCMOS33 } [get_ports { sw_bitpos[6] }]; # sw[6]
## sw[7]-sw[15] (pins P2,P1,N2,N1,M2,M1,L1,K2,K1) are unused by this design

## ---- LEDs (board has 16: led[0]-led[15], we use 4) ----
set_property -dict { PACKAGE_PIN G1 IOSTANDARD LVCMOS33 } [get_ports { led_pass      }]; # led[0]
set_property -dict { PACKAGE_PIN G2 IOSTANDARD LVCMOS33 } [get_ports { led_sec       }]; # led[1]
set_property -dict { PACKAGE_PIN F1 IOSTANDARD LVCMOS33 } [get_ports { led_ded       }]; # led[2]
set_property -dict { PACKAGE_PIN F2 IOSTANDARD LVCMOS33 } [get_ports { led_heartbeat }]; # led[3]
## led[4]-led[15] are unused by this design

## ---- config options ----
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
