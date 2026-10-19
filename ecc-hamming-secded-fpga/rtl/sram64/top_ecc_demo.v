// ============================================================================
// top_ecc_demo.v
// Board-level demo/test harness for the ECC SRAM wrapper.
//
// Usage on the board:
//   1. Press BTN_STEP  -> writes an auto-incrementing test pattern to the
//                          next address, then reads it back (no fault yet).
//                          LED_PASS should light (data matched, no error).
//   2. Set switches SW[6:0] to a bit position (0..71) you want to corrupt.
//   3. Press BTN_INJECT -> flips that bit in the just-written word, then
//                          automatically re-reads it.
//                          LED_SEC lights if it was corrected (single-bit).
//                          LED_DED lights if flagged uncorrectable (2-bit --
//                          you'd need two BTN_INJECT presses at different
//                          bit positions before a BTN_STEP to see this).
//   4. Press BTN_CLEAR  -> resets the statistics counters.
//
// Adjust port names/widths to match your specific Spartan-7 board's
// switches/buttons/LEDs (see constraints/example.xdc).
// ============================================================================
`timescale 1ns / 1ps

module top_ecc_demo #(
    parameter ADDR_WIDTH = 8
)(
    input  wire        clk100,          // board oscillator, e.g. 100 MHz
    input  wire        btn_step,
    input  wire        btn_inject,
    input  wire        btn_clear,
    input  wire [6:0]  sw_bitpos,       // bit position to corrupt (0..71)

    output wire        led_pass,        // last read matched expected data, no error
    output wire        led_sec,         // last read had a corrected single-bit error
    output wire        led_ded,         // last read had an uncorrectable double-bit error
    output wire        led_heartbeat
);

    // ---- reset generation (simple power-on reset via counter) ----
    reg [3:0] rst_cnt = 4'd0;
    reg       rst = 1'b1;
    always @(posedge clk100) begin
        if (rst_cnt != 4'hF) begin
            rst_cnt <= rst_cnt + 1'b1;
            rst <= 1'b1;
        end else begin
            rst <= 1'b0;
        end
    end

    // ---- button debounce/edge-detect (very simple, 1 sample delay) ----
    reg step_d, inject_d, clear_d;
    always @(posedge clk100) begin
        step_d   <= btn_step;
        inject_d <= btn_inject;
        clear_d  <= btn_clear;
    end
    wire step_pulse   = btn_step   && !step_d;
    wire inject_pulse = btn_inject && !inject_d;
    wire clear_pulse  = btn_clear  && !clear_d;

    // ---- ECC SRAM wrapper signals ----
    reg                    we;
    reg  [ADDR_WIDTH-1:0]  addr;
    reg  [63:0]            din;
    wire [63:0]            dout;
    wire                   sec_flag, ded_flag, dout_valid;

    // fault-injector -> memory wires (declared before use)
    wire                   inject_en_w;
    wire [ADDR_WIDTH-1:0]  inject_addr_w;
    wire [6:0]             inject_bitpos_w;

    fault_injector #(.ADDR_WIDTH(ADDR_WIDTH)) u_injector (
        .clk            (clk100),
        .rst            (rst),
        .trigger        (inject_pulse),
        .target_addr    (addr),
        .target_bitpos  (sw_bitpos),
        .inject_en      (inject_en_w),
        .inject_addr    (inject_addr_w),
        .inject_bitpos  (inject_bitpos_w)
    );

    ecc_sram_wrapper #(.ADDR_WIDTH(ADDR_WIDTH)) u_ecc_sram (
        .clk            (clk100),
        .rst            (rst),
        .we             (we),
        .addr           (addr),
        .din            (din),
        .dout           (dout),
        .sec_flag       (sec_flag),
        .ded_flag       (ded_flag),
        .dout_valid     (dout_valid),
        .inject_en      (inject_en_w),
        .inject_addr    (inject_addr_w),
        .inject_bitpos  (inject_bitpos_w)
    );

    stats_logger #(.CNT_WIDTH(32)) u_stats (
        .clk          (clk100),
        .rst          (rst),
        .clear        (clear_pulse),
        .dout_valid   (dout_valid),
        .sec_flag     (sec_flag),
        .ded_flag     (ded_flag),
        .total_reads  (),
        .sec_count    (),
        .ded_count    ()
    );

    // ---- simple test FSM ----
    localparam S_IDLE = 0, S_WRITE = 1, S_READ_WAIT = 2, S_DONE = 3;
    // The wrapper's read pipeline (plus the injector's output register) needs
    // ~5 clock cycles before sec/ded/dout reflect a NEW write or injection.
    // dout_valid is already high while idle, so it must NOT be used as the
    // "result is ready" signal -- wait a fixed settle time instead.
    localparam SETTLE = 8;
    reg [3:0] wait_cnt;
    reg [1:0] state;
    reg [ADDR_WIDTH-1:0] cur_addr;
    reg [63:0] expected_data;
    reg [63:0] test_counter;

    reg led_pass_r, led_sec_r, led_ded_r;

    always @(posedge clk100) begin
        if (rst) begin
            state         <= S_IDLE;
            wait_cnt      <= 4'd0;
            we            <= 1'b0;
            addr          <= {ADDR_WIDTH{1'b0}};
            din           <= 64'd0;
            cur_addr      <= {ADDR_WIDTH{1'b0}};
            test_counter  <= 64'd1;
            expected_data <= 64'd0;
            led_pass_r    <= 1'b0;
            led_sec_r     <= 1'b0;
            led_ded_r     <= 1'b0;
        end else begin
            we <= 1'b0; // default: no write unless explicitly set below

            case (state)
                S_IDLE: begin
                    if (step_pulse) begin
                        // write a fresh test pattern to the current address
                        din  <= test_counter;
                        addr <= cur_addr;
                        we   <= 1'b1;
                        expected_data <= test_counter;
                        state <= S_READ_WAIT; wait_cnt <= 4'd0;
                    end else if (inject_pulse) begin
                        // re-read the same address after the injector flips a bit
                        addr <= cur_addr;
                        state <= S_READ_WAIT; wait_cnt <= 4'd0;
                    end
                end

                S_READ_WAIT: begin
                    // hold address steady while the new result propagates
                    wait_cnt <= wait_cnt + 1'b1;
                    if (wait_cnt == SETTLE - 1 && dout_valid) begin
                        led_pass_r <= (!sec_flag) && (!ded_flag) && (dout == expected_data);
                        led_sec_r  <= sec_flag;
                        led_ded_r  <= ded_flag;
                        state      <= S_DONE;
                    end
                end

                S_DONE: begin
                    // advance to next address on the next write, wrap around
                    if (step_pulse) begin
                        cur_addr     <= cur_addr + 1'b1;
                        test_counter <= test_counter + 64'h0100_0001;
                        din          <= test_counter + 64'h0100_0001;
                        addr         <= cur_addr + 1'b1;
                        we           <= 1'b1;
                        expected_data <= test_counter + 64'h0100_0001;
                        state        <= S_READ_WAIT; wait_cnt <= 4'd0;
                    end else if (inject_pulse) begin
                        addr  <= cur_addr;
                        state <= S_READ_WAIT; wait_cnt <= 4'd0;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    assign led_pass = led_pass_r;
    assign led_sec  = led_sec_r;
    assign led_ded  = led_ded_r;

    // heartbeat so you can confirm the design is alive/clocked on the board
    reg [23:0] hb_cnt;
    always @(posedge clk100) hb_cnt <= hb_cnt + 1'b1;
    assign led_heartbeat = hb_cnt[23];

endmodule
