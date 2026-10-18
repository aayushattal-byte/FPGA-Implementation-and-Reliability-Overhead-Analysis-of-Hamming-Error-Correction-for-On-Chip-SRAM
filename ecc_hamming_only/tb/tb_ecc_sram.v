// ============================================================================
// tb_ecc_sram.v
// Self-checking testbench for the ECC SRAM wrapper (single-file RTL version).
// Run in Vivado's xsim, or with Icarus Verilog -- see README.
//
// Tests 1-3: basic correctness (round trip, single-bit correct, double-bit
//            detect) -- same as before, sanity checks.
// Test 4:    multi-bit fault sweep. Injects exactly 1, then 2, then 3
//            DISTINCT random bit flips per word (200 trials each) and
//            tallies three outcomes per trial:
//              - corrected:    sec_flag=1 and data matches original  (good)
//              - detected:     ded_flag=1                            (good --
//                               caught, even though not fixed)
//              - MISCORRECTED: sec_flag=1 but data does NOT match    (bad --
//                               silently returned wrong data with no warning)
//            This is the experiment that shows Hamming SECDED's guarantee
//            (correct 1, detect 2) and where it breaks down at 3+ flips.
// ============================================================================
`timescale 1ns / 1ps

module tb_ecc_sram;

    localparam ADDR_WIDTH = 8;

    reg clk = 0;
    reg rst = 1;
    reg we;
    reg [ADDR_WIDTH-1:0] addr;
    reg [63:0] din;
    wire [63:0] dout;
    wire sec_flag, ded_flag, dout_valid;

    reg inject_en;
    reg [ADDR_WIDTH-1:0] inject_addr;
    reg [6:0] inject_bitpos;

    integer pass_count, fail_count;
    integer i, j, n;
    reg [63:0] pattern;
    reg [6:0] bitpos_used [0:2];   // up to 3 distinct positions per trial
    integer pool [0:71];           // used for Fisher-Yates distinct-position pick
    integer p, r_idx, tmp;

    // per-fault-count tallies, reused for n=1,2,3
    integer corrected_cnt, detected_cnt, miscorrected_cnt;

    ecc_sram_wrapper #(.ADDR_WIDTH(ADDR_WIDTH)) DUT (
        .clk(clk), .rst(rst),
        .we(we), .addr(addr), .din(din),
        .dout(dout), .sec_flag(sec_flag), .ded_flag(ded_flag), .dout_valid(dout_valid),
        .inject_en(inject_en), .inject_addr(inject_addr), .inject_bitpos(inject_bitpos)
    );

    always #5 clk = ~clk;   // 100 MHz

    // control signals driven on negedge so the DUT samples clean one-cycle
    // pulses on posedge (avoids a blocking-assignment race)
    task write_word(input [ADDR_WIDTH-1:0] a, input [63:0] d);
        begin
            @(negedge clk);
            we = 1; addr = a; din = d;
            @(negedge clk);
            we = 0;
        end
    endtask

    task read_word(input [ADDR_WIDTH-1:0] a);
        begin
            @(negedge clk);
            addr = a;
            wait (dout_valid == 1'b1);
            @(negedge clk);
        end
    endtask

    task inject_bit(input [ADDR_WIDTH-1:0] a, input [6:0] bitpos);
        begin
            @(negedge clk);
            inject_en = 1; inject_addr = a; inject_bitpos = bitpos;
            @(negedge clk);
            inject_en = 0;
        end
    endtask

    initial begin
        we = 0; addr = 0; din = 0;
        inject_en = 0; inject_addr = 0; inject_bitpos = 0;
        pass_count = 0; fail_count = 0;

        repeat (3) @(posedge clk);
        rst = 0;
        repeat (3) @(posedge clk);

        // ---------------- Test 1: plain round trip ----------------
        write_word(8'd0, 64'hDEAD_BEEF_1234_5678);
        read_word(8'd0);
        if (dout === 64'hDEAD_BEEF_1234_5678 && !sec_flag && !ded_flag) begin
            $display("[PASS] Test 1: plain round trip, data=%h", dout);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Test 1: got %h sec=%b ded=%b", dout, sec_flag, ded_flag);
            fail_count = fail_count + 1;
        end

        // ---------------- Test 2: single-bit error, must correct ----------------
        write_word(8'd1, 64'hCAFEBABE_0F0F0F0F);
        inject_bit(8'd1, 7'd37);
        read_word(8'd1);
        if (dout === 64'hCAFEBABE_0F0F0F0F && sec_flag && !ded_flag) begin
            $display("[PASS] Test 2: single-bit error corrected, data=%h", dout);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Test 2: data=%h sec=%b ded=%b", dout, sec_flag, ded_flag);
            fail_count = fail_count + 1;
        end

        // ---------------- Test 3: double-bit error, must detect ----------------
        write_word(8'd2, 64'h1111_2222_3333_4444);
        inject_bit(8'd2, 7'd10);
        inject_bit(8'd2, 7'd50);
        read_word(8'd2);
        if (ded_flag) begin
            $display("[PASS] Test 3: double-bit error correctly flagged uncorrectable");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Test 3: expected ded_flag=1, got sec=%b ded=%b", sec_flag, ded_flag);
            fail_count = fail_count + 1;
        end

        $display("--------------------------------------------------");
        $display("Basic tests: %0d passed, %0d failed", pass_count, fail_count);
        $display("--------------------------------------------------");

        // ---------------- Test 4: multi-bit fault sweep (1, 2, 3 flips) ----------------
        for (n = 1; n <= 3; n = n + 1) begin
            corrected_cnt = 0; detected_cnt = 0; miscorrected_cnt = 0;

            for (i = 0; i < 200; i = i + 1) begin
                pattern = {$random, $random};
                write_word(i[ADDR_WIDTH-1:0], pattern);

                // pick n DISTINCT random bit positions (0..71) via a partial
                // Fisher-Yates shuffle -- single deterministic pass, no retry
                // loop, so there is no zero-time while-loop for the simulator
                // to handle inconsistently
                for (p = 0; p < 72; p = p + 1) pool[p] = p;
                for (p = 0; p < n; p = p + 1) begin
                    r_idx = p + ($unsigned($random) % (72 - p));
                    tmp = pool[p]; pool[p] = pool[r_idx]; pool[r_idx] = tmp;
                    bitpos_used[p] = pool[p][6:0];
                end

                for (j = 0; j < n; j = j + 1)
                    inject_bit(i[ADDR_WIDTH-1:0], bitpos_used[j]);

                read_word(i[ADDR_WIDTH-1:0]);

                if (i < 3) begin
                    // print the actual positions used for the first few trials
                    // of each n, so a stuck/broken RNG would be visible immediately
                    if (n == 1) $display("  [debug] n=1 trial %0d: flipped bit %0d", i, bitpos_used[0]);
                    if (n == 2) $display("  [debug] n=2 trial %0d: flipped bits %0d,%0d", i, bitpos_used[0], bitpos_used[1]);
                    if (n == 3) $display("  [debug] n=3 trial %0d: flipped bits %0d,%0d,%0d", i, bitpos_used[0], bitpos_used[1], bitpos_used[2]);
                end

                read_word(i[ADDR_WIDTH-1:0]);

                if (ded_flag) begin
                    detected_cnt = detected_cnt + 1;
                end else if (sec_flag) begin
                    if (dout === pattern)
                        corrected_cnt = corrected_cnt + 1;
                    else
                        miscorrected_cnt = miscorrected_cnt + 1;  // silently WRONG, no flag raised
                end else begin
                    // no flag raised at all -- only expected/safe when n=0, should not happen here
                    if (dout !== pattern) miscorrected_cnt = miscorrected_cnt + 1;
                    else corrected_cnt = corrected_cnt + 1; // coincidentally still matched
                end
            end

            $display("[INFO] %0d bit flip(s) per word, 200 trials: %0d corrected, %0d detected-uncorrectable, %0d SILENTLY MISCORRECTED",
                      n, corrected_cnt, detected_cnt, miscorrected_cnt);
        end

        $display("--------------------------------------------------");
        $display("Expected pattern: at 1 flip -> ~200 corrected, 0 detected, 0 miscorrected");
        $display("                  at 2 flips -> 0 corrected, ~200 detected, 0 miscorrected");
        $display("                  at 3 flips -> mix, and MISCORRECTED > 0 is expected here --");
        $display("                  that's Hamming SECDED's guarantee (1 correct / 2 detect) breaking");
        $display("                  down beyond its design limit, exactly as ECC theory predicts.");
        $display("--------------------------------------------------");

        if (fail_count == 0)
            $display("ALL BASIC TESTS PASSED -- see Test 4 sweep above for the reliability study data");
        else
            $display("SOME BASIC TESTS FAILED -- check log above");

        $finish;
    end

endmodule
