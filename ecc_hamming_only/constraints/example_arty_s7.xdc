## ============================================================================
## example_arty_s7.xdc
##
## TEMPLATE constraints file, written against the Digilent Arty S7 (Spartan-7
## XC7S50/XC7S25) pin naming convention. If your board is a different
## Spartan-7 board, replace every LOC value below with the correct pin from
## YOUR board's master XDC (search "<your board name> master xdc digilent"
## or check your board's reference manual). Signal NAMES (clk100, btn_step,
## etc.) must match top_ecc_demo.v's port list -- only the LOC/IOSTANDARD
## lines are board-specific.
## ============================================================================

## ---- 100 MHz system clock ----
set_property -dict { PACKAGE_PIN R2  IOSTANDARD LVCMOS33 } [get_ports { clk100 }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk100 }];

## ---- push buttons ----
set_property -dict { PACKAGE_PIN G15 IOSTANDARD LVCMOS33 } [get_ports { btn_step   }]; # BTN0
set_property -dict { PACKAGE_PIN K16 IOSTANDARD LVCMOS33 } [get_ports { btn_inject }]; # BTN1
set_property -dict { PACKAGE_PIN J16 IOSTANDARD LVCMOS33 } [get_ports { btn_clear  }]; # BTN2

## ---- switches (only need 7 for bit position 0..71) ----
set_property -dict { PACKAGE_PIN H14 IOSTANDARD LVCMOS33 } [get_ports { sw_bitpos[0] }];
set_property -dict { PACKAGE_PIN H18 IOSTANDARD LVCMOS33 } [get_ports { sw_bitpos[1] }];
set_property -dict { PACKAGE_PIN G18 IOSTANDARD LVCMOS33 } [get_ports { sw_bitpos[2] }];
set_property -dict { PACKAGE_PIN M5  IOSTANDARD LVCMOS33 } [get_ports { sw_bitpos[3] }];
set_property -dict { PACKAGE_PIN N3  IOSTANDARD LVCMOS33 } [get_ports { sw_bitpos[4] }];
set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 } [get_ports { sw_bitpos[5] }];
set_property -dict { PACKAGE_PIN P16 IOSTANDARD LVCMOS33 } [get_ports { sw_bitpos[6] }];

## ---- LEDs ----
set_property -dict { PACKAGE_PIN E18 IOSTANDARD LVCMOS33 } [get_ports { led_pass      }];
set_property -dict { PACKAGE_PIN F13 IOSTANDARD LVCMOS33 } [get_ports { led_sec       }];
set_property -dict { PACKAGE_PIN E13 IOSTANDARD LVCMOS33 } [get_ports { led_ded       }];
set_property -dict { PACKAGE_PIN H15 IOSTANDARD LVCMOS33 } [get_ports { led_heartbeat }];

## ---- config options (typical for Spartan-7 boards) ----
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
