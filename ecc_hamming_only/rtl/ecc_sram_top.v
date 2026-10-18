// ============================================================================
// ecc_sram_top.v
// Hamming(72,64) SECDED-protected SRAM -- SINGLE FILE, all modules included.
// Just add this ONE file to Vivado as a design source and you're set.
//
// Module list in this file (in order):
//   hamming_encoder   - 64-bit data -> 72-bit SECDED codeword
//   hamming_decoder   - 72-bit codeword -> corrected 64-bit data + sec/ded flags
//   ecc_sram_wrapper  - wraps inferred Block RAM with the above (2-cycle read latency)
//   fault_injector    - edge-triggered controller to flip a bit in stored memory
//   stats_logger      - counters: total reads, corrected errors, uncorrectable errors
//   top_ecc_demo      - board-level top: buttons drive a test FSM, LEDs show status
//
// Set 'top_ecc_demo' as the top module for implementation in Vivado.
// ============================================================================
// ============================================================================
// hamming_encoder.v
// Hamming(72,64) SECDED encoder.
//
// Takes 64 bits of data and produces a 72-bit codeword:
//   codeword[71:1] = 71-bit classic Hamming code (interleaved data + 7 parity
//                     bits, positions 1..71, position = index)
//   codeword[0]    = overall (extra) parity bit -> makes it SECDED
//
// Position rule (classic Hamming): positions that are powers of two (1, 2, 4,
// 8, 16, 32, 64) hold parity bits. All other positions (1..71 minus those 7)
// hold the 64 data bits, in order.
//
// Parity bit at position 2^i is the XOR of every data bit whose position has
// bit i set in its binary representation.
// ============================================================================
`timescale 1ns / 1ps

module hamming_encoder (
    input  wire [63:0] data_in,
    output reg  [71:0] codeword
);

    integer k, i, p;
    reg [71:1] positions;   // positions[1..71]
    reg parity;

    // returns 1 if x is a power of two (1,2,4,8,...), else 0
    function integer is_pow2;
        input integer x;
        begin
            is_pow2 = (x != 0) && ((x & (x - 1)) == 0);
        end
    endfunction

    // maps data bit index k (0..63) to its virtual codeword position (1..71)
    function integer bitpos;
        input integer k;
        integer pp, cnt;
        begin
            cnt    = -1;
            bitpos = 0;
            for (pp = 1; pp <= 71; pp = pp + 1) begin
                if (!is_pow2(pp)) begin
                    cnt = cnt + 1;
                    if (cnt == k) bitpos = pp;
                end
            end
        end
    endfunction

    always @* begin
        // 1) place the 64 data bits into their non-power-of-two positions
        for (k = 0; k < 64; k = k + 1) begin
            positions[bitpos(k)] = data_in[k];
        end

        // 2) compute the 7 Hamming parity bits (positions 1,2,4,8,16,32,64)
        for (i = 0; i < 7; i = i + 1) begin
            parity = 1'b0;
            for (p = 1; p <= 71; p = p + 1) begin
                if (!is_pow2(p)) begin
                    if ((p & (1 << i)) != 0)
                        parity = parity ^ positions[p];
                end
            end
            positions[1 << i] = parity;
        end

        // 3) assemble codeword + overall (SECDED) parity bit
        codeword[71:1] = positions;
        codeword[0]    = ^positions;   // even parity over all 71 bits
    end

endmodule
// ============================================================================
// hamming_decoder.v
// Hamming(72,64) SECDED decoder / corrector.
//
// Given a (possibly corrupted) 72-bit codeword, recomputes the syndrome and:
//   - syndrome == 0, overall_parity == 0  -> no error
//   - syndrome == 0, overall_parity == 1  -> error in the overall parity bit
//                                            only (data unaffected) -> SEC
//   - syndrome != 0, overall_parity == 1  -> single-bit error in the 71-bit
//                                            Hamming field, at position
//                                            'syndrome' -> corrected -> SEC
//   - syndrome != 0, overall_parity == 0  -> double-bit error -> DED
//                                            (uncorrectable, data flagged bad)
// ============================================================================
`timescale 1ns / 1ps

module hamming_decoder (
    input  wire [71:0] codeword_in,
    output reg  [63:0] data_out,
    output reg          sec,     // 1 = single-bit error was found & corrected
    output reg          ded      // 1 = double-bit error detected (uncorrectable)
);

    integer k, i, p;
    reg [71:1] positions;
    reg [71:1] corrected;
    reg [6:0]  syndrome;
    reg        overall_parity;
    reg        parity;

    function integer is_pow2;
        input integer x;
        begin
            is_pow2 = (x != 0) && ((x & (x - 1)) == 0);
        end
    endfunction

    function integer bitpos;
        input integer k;
        integer pp, cnt;
        begin
            cnt    = -1;
            bitpos = 0;
            for (pp = 1; pp <= 71; pp = pp + 1) begin
                if (!is_pow2(pp)) begin
                    cnt = cnt + 1;
                    if (cnt == k) bitpos = pp;
                end
            end
        end
    endfunction

    always @* begin
        positions = codeword_in[71:1];

        // recompute the 7-bit syndrome: each bit i = XOR of ALL positions
        // (including the parity bit itself) whose index has bit i set
        for (i = 0; i < 7; i = i + 1) begin
            parity = 1'b0;
            for (p = 1; p <= 71; p = p + 1) begin
                if ((p & (1 << i)) != 0)
                    parity = parity ^ positions[p];
            end
            syndrome[i] = parity;
        end

        overall_parity = codeword_in[0] ^ (^positions);

        corrected = positions;
        sec = 1'b0;
        ded = 1'b0;

        if (syndrome == 7'd0 && overall_parity == 1'b0) begin
            // no error, nothing to do
        end else if (syndrome == 7'd0 && overall_parity == 1'b1) begin
            // error is in the overall parity bit only; data is fine
            sec = 1'b1;
        end else if (syndrome != 7'd0 && overall_parity == 1'b1) begin
            // single-bit error inside the 71-bit field -> correct it
            corrected[syndrome] = ~positions[syndrome];
            sec = 1'b1;
        end else begin
            // syndrome != 0 and overall_parity == 0 -> two-bit error
            ded = 1'b1;
        end

        // extract the (corrected) 64 data bits back out
        for (k = 0; k < 64; k = k + 1) begin
            data_out[k] = corrected[bitpos(k)];
        end
    end

endmodule
// ============================================================================
// ecc_sram_wrapper.v
// SECDED-protected memory. Wraps an inferred Xilinx Block RAM with a Hamming
// encoder on the write path and a Hamming decoder on the read path.
//
// Timing:
//   - Write: data is encoded combinationally, written to mem[addr] same cycle
//            'we' is asserted.
//   - Read : 2-cycle latency from 'addr' valid to 'dout' valid
//              cycle 0: address presented, codeword read out of BRAM
//              cycle 1: codeword decoded/corrected, result registered on dout
//
// A separate fault-injection port lets you flip a single bit of the STORED
// codeword directly (bypassing the encoder) to emulate an SEU, without
// touching the normal read/write ports.
// ============================================================================
`timescale 1ns / 1ps

module ecc_sram_wrapper #(
    parameter ADDR_WIDTH = 8,                    // 256 x 64-bit words by default
    parameter DEPTH      = (1 << ADDR_WIDTH)
)(
    input  wire                   clk,
    input  wire                   rst,

    // normal read/write port
    input  wire                   we,
    input  wire [ADDR_WIDTH-1:0]  addr,
    input  wire [63:0]            din,
    output reg  [63:0]            dout,
    output reg                    sec_flag,      // pulses when a read hit a corrected 1-bit error
    output reg                    ded_flag,       // pulses when a read hit an uncorrectable 2-bit error
    output reg                    dout_valid,     // 1 when dout/sec_flag/ded_flag are valid this cycle

    // fault-injection port (for reliability testing)
    input  wire                   inject_en,
    input  wire [ADDR_WIDTH-1:0]  inject_addr,
    input  wire [6:0]             inject_bitpos   // which bit (0..71) of the stored codeword to flip
);

    // ---- write path: encode then store ----
    wire [71:0] encoded_wr;
    hamming_encoder u_enc (
        .data_in  (din),
        .codeword (encoded_wr)
    );

    (* ram_style = "block" *) reg [71:0] mem [0:DEPTH-1];

    // ---- read path ----
    reg [71:0] rd_codeword;
    reg        rd_valid_p0;   // address was presented at t, codeword captured at t+1

    wire [63:0] decoded_data;
    wire        dec_sec, dec_ded;

    hamming_decoder u_dec (
        .codeword_in (rd_codeword),
        .data_out    (decoded_data),
        .sec         (dec_sec),
        .ded         (dec_ded)
    );

    always @(posedge clk) begin
        if (rst) begin
            rd_valid_p0 <= 1'b0;
            dout_valid  <= 1'b0;
            sec_flag    <= 1'b0;
            ded_flag    <= 1'b0;
        end else begin
            // priority: fault injection > write > read
            if (inject_en) begin
                mem[inject_addr][inject_bitpos] <= ~mem[inject_addr][inject_bitpos];
            end else if (we) begin
                mem[addr] <= encoded_wr;
            end

            // pipeline stage 0: capture codeword for this address
            rd_codeword <= mem[addr];
            rd_valid_p0 <= (!we) && (!inject_en);

            // pipeline stage 1: decode result becomes valid this cycle,
            // aligned with rd_codeword captured last cycle
            dout        <= decoded_data;
            sec_flag    <= dec_sec && rd_valid_p0;
            ded_flag    <= dec_ded && rd_valid_p0;
            dout_valid  <= rd_valid_p0;
        end
    end

endmodule
// ============================================================================
// fault_injector.v
// Simple edge-triggered controller for the ecc_sram_wrapper's inject port.
// On a rising edge of 'trigger', pulses inject_en for one cycle at the given
// address/bit position. Debounced trigger recommended if driven from a
// physical button (see top-level).
// ============================================================================
`timescale 1ns / 1ps

module fault_injector #(
    parameter ADDR_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  trigger,        // rising-edge = "flip a bit now"
    input  wire [ADDR_WIDTH-1:0] target_addr,
    input  wire [6:0]            target_bitpos,

    output reg                   inject_en,
    output reg  [ADDR_WIDTH-1:0] inject_addr,
    output reg  [6:0]            inject_bitpos
);

    reg trigger_d;

    always @(posedge clk) begin
        if (rst) begin
            trigger_d     <= 1'b0;
            inject_en     <= 1'b0;
            inject_addr   <= {ADDR_WIDTH{1'b0}};
            inject_bitpos <= 7'd0;
        end else begin
            trigger_d <= trigger;
            inject_en <= trigger && !trigger_d;   // one-cycle pulse on rising edge
            inject_addr   <= target_addr;
            inject_bitpos <= target_bitpos;
        end
    end

endmodule
// ============================================================================
// stats_logger.v
// Free-running counters for the reliability study:
//   - total_reads : every cycle dout_valid is high
//   - sec_count   : every cycle sec_flag is high (corrected single-bit errors)
//   - ded_count   : every cycle ded_flag is high (uncorrectable double-bit errors)
// Read these out over UART/AXI/switches+LEDs to build your overhead-vs-
// reliability plots.
// ============================================================================
`timescale 1ns / 1ps

module stats_logger #(
    parameter CNT_WIDTH = 32
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   clear,          // synchronous counter clear
    input  wire                   dout_valid,
    input  wire                   sec_flag,
    input  wire                   ded_flag,

    output reg [CNT_WIDTH-1:0]    total_reads,
    output reg [CNT_WIDTH-1:0]    sec_count,
    output reg [CNT_WIDTH-1:0]    ded_count
);

    always @(posedge clk) begin
        if (rst || clear) begin
            total_reads <= {CNT_WIDTH{1'b0}};
            sec_count   <= {CNT_WIDTH{1'b0}};
            ded_count   <= {CNT_WIDTH{1'b0}};
        end else begin
            if (dout_valid) total_reads <= total_reads + 1'b1;
            if (sec_flag)   sec_count   <= sec_count   + 1'b1;
            if (ded_flag)   ded_count   <= ded_count   + 1'b1;
        end
    end

endmodule
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

    reg                    inject_en_req;
    reg  [ADDR_WIDTH-1:0]  inject_addr_req;

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
    wire inject_en_w;
    wire [ADDR_WIDTH-1:0] inject_addr_w;
    wire [6:0] inject_bitpos_w;

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
    reg [1:0] state;
    reg [ADDR_WIDTH-1:0] cur_addr;
    reg [63:0] expected_data;
    reg [63:0] test_counter;

    reg led_pass_r, led_sec_r, led_ded_r;

    always @(posedge clk100) begin
        if (rst) begin
            state         <= S_IDLE;
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
                        state <= S_READ_WAIT;
                    end else if (inject_pulse) begin
                        // re-read the same address after the injector flips a bit
                        addr <= cur_addr;
                        state <= S_READ_WAIT;
                    end
                end

                S_READ_WAIT: begin
                    // hold address steady; wrapper has 2-cycle read latency
                    if (dout_valid) begin
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
                        state        <= S_READ_WAIT;
                    end else if (inject_pulse) begin
                        addr  <= cur_addr;
                        state <= S_READ_WAIT;
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
