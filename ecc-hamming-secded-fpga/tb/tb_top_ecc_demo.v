// ============================================================================
// tb_top_ecc_demo.v -- board-level test: drives the buttons/switches of
// top_ecc_demo exactly as a person would and checks the LEDs.
//   step   -> LED_PASS            (clean write + read-back)
//   inject -> LED_SEC             (single-bit error corrected)
//   step   -> LED_PASS            (new word, previous error gone)
//   inject, inject -> LED_DED     (two different bits in the same word)
// Button presses are held for 20 cycles (a real press lasts milliseconds).
// ============================================================================
`timescale 1ns / 1ps
module tb_top_ecc_demo;
    reg clk100 = 0;
    reg btn_step = 0, btn_inject = 0, btn_clear = 0;
    reg [6:0] sw_bitpos = 0;
    wire led_pass, led_sec, led_ded, led_heartbeat;
    integer errors = 0;

    top_ecc_demo dut (.clk100(clk100), .btn_step(btn_step), .btn_inject(btn_inject),
                      .btn_clear(btn_clear), .sw_bitpos(sw_bitpos),
                      .led_pass(led_pass), .led_sec(led_sec), .led_ded(led_ded),
                      .led_heartbeat(led_heartbeat));
    always #5 clk100 = ~clk100;

    task press_step;   begin @(negedge clk100); btn_step = 1;   repeat (20) @(negedge clk100); btn_step = 0;   repeat (40) @(negedge clk100); end endtask
    task press_inject; begin @(negedge clk100); btn_inject = 1; repeat (20) @(negedge clk100); btn_inject = 0; repeat (40) @(negedge clk100); end endtask

    task expect_leds(input [255:0] what, input p, input s, input d);
        begin
            if ({led_pass, led_sec, led_ded} === {p, s, d})
                $display("[PASS] %0s: pass=%b sec=%b ded=%b", what, led_pass, led_sec, led_ded);
            else begin
                $display("[FAIL] %0s: pass=%b sec=%b ded=%b  (expected %b %b %b)", what, led_pass, led_sec, led_ded, p, s, d);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (40) @(negedge clk100);                 // power-on reset
        press_step;                          expect_leds("step (clean write/read)      ", 1, 0, 0);
        sw_bitpos = 7'd37; press_inject;     expect_leds("inject 1 bit (bit 37)        ", 0, 1, 0);
        press_step;                          expect_leds("step again (fresh word)      ", 1, 0, 0);
        sw_bitpos = 7'd10; press_inject;     expect_leds("inject bit 10                ", 0, 1, 0);
        sw_bitpos = 7'd50; press_inject;     expect_leds("inject bit 50 (2nd error)    ", 0, 0, 1);
        $display("[VERDICT] %s (%0d board-level check(s) failed)", errors == 0 ? "PASS" : "FAIL", errors);
        $finish;
    end
endmodule
