`timescale 1ns / 1ps

module tb_hamming_13_8;

    reg clk = 0;
    reg rst = 1;
    reg enable;
    reg [7:0] data_in;
    wire [12:0] code_out;

    reg [12:0] code_in;
    wire [7:0] data_out;
    wire error_detect, error_correct, double_error;

    integer pass_count = 0;
    integer fail_count = 0;

    reg [7:0] data_in_ref;
    reg [12:0] clean_code;
    integer fi, fj, fk;
    integer n_correct_match, n_correct_wrong, n_double, n_noflag_match, n_noflag_wrong;
    integer first_wrong_i, first_wrong_j, first_wrong_k;
    reg [7:0] first_wrong_data;

    ecc_encoder u_enc (
        .clk(clk), .rst(rst), .data_in(data_in), .enable(enable), .code_out(code_out)
    );

    ecc_decoder u_dec (
        .clk(clk), .rst(rst), .code_in(code_in), .data_out(data_out),
        .error_detect(error_detect), .error_correct(error_correct), .double_error(double_error)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("hamming_13_8.vcd");
        $dumpvars(0, tb_hamming_13_8);

        enable = 0; data_in = 8'd0; code_in = 13'd0;
        repeat (3) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);

        // ---- Case 1: encode a data word, feed straight through, no error ----
        @(negedge clk); enable = 1; data_in = 8'b1011_0101;
        @(negedge clk); enable = 0;
        @(negedge clk); code_in = code_out;   // no corruption
        @(negedge clk);
        if (data_out === 8'b1011_0101 && !error_detect) begin
            $display("[PASS] Case 1: clean round trip, data_out=%b", data_out);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Case 1: data_out=%b error_detect=%b", data_out, error_detect);
            fail_count = fail_count + 1;
        end

        // ---- Case 2: single-bit error, must correct ----
        @(negedge clk); enable = 1; data_in = 8'b1100_1010;
        @(negedge clk); enable = 0;
        @(negedge clk); code_in = code_out ^ 13'b0_0000_0000_1000; // flip bit 3
        @(negedge clk);
        if (data_out === 8'b1100_1010 && error_correct && !double_error) begin
            $display("[PASS] Case 2: single-bit error corrected, data_out=%b", data_out);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Case 2: data_out=%b error_correct=%b double_error=%b",
                       data_out, error_correct, double_error);
            fail_count = fail_count + 1;
        end

        // ---- Case 3: double-bit error, must detect (not silently miscorrect) ----
        @(negedge clk); enable = 1; data_in = 8'b0110_1100;
        @(negedge clk); enable = 0;
        @(negedge clk); code_in = code_out ^ 13'b0_0000_0001_0001; // flip bits 0 and 4
        @(negedge clk);
        if (double_error) begin
            $display("[PASS] Case 3: double-bit error correctly flagged uncorrectable");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Case 3: double_error=%b error_correct=%b", double_error, error_correct);
            fail_count = fail_count + 1;
        end

        // ---- Case 4: EXHAUSTIVE 3-bit-error sweep -----------------------
        // Hamming(13,8) SECDED is only *guaranteed* to correct 1 bit and
        // detect 2 bits. This sweep tries every possible combination of
        // 3 simultaneously-flipped bits (13-choose-3 = 286 combinations)
        // against one fixed encoded word, to show exactly what happens
        // once the error count exceeds that guarantee.
        data_in_ref = 8'b1010_0110;
        @(negedge clk); enable = 1; data_in = data_in_ref;
        @(negedge clk); enable = 0;
        @(negedge clk); clean_code = code_out;

        n_correct_match = 0; n_correct_wrong = 0; n_double = 0;
        n_noflag_match = 0; n_noflag_wrong = 0;
        first_wrong_i = -1; first_wrong_j = -1; first_wrong_k = -1;
        first_wrong_data = 8'd0;

        for (fi = 0; fi < 13; fi = fi + 1)
          for (fj = fi + 1; fj < 13; fj = fj + 1)
            for (fk = fj + 1; fk < 13; fk = fk + 1) begin
                @(negedge clk);
                code_in = clean_code ^ ((13'b1 << fi) | (13'b1 << fj) | (13'b1 << fk));
                @(negedge clk); // one clock edge later, decoder outputs have settled

                if (double_error) begin
                    n_double = n_double + 1;
                end else if (error_correct) begin
                    if (data_out === data_in_ref) begin
                        n_correct_match = n_correct_match + 1;
                    end else begin
                        n_correct_wrong = n_correct_wrong + 1;
                        if (first_wrong_i == -1) begin
                            first_wrong_i = fi; first_wrong_j = fj; first_wrong_k = fk;
                            first_wrong_data = data_out;
                        end
                    end
                end else begin
                    // no flag raised at all
                    if (data_out === data_in_ref) begin
                        n_noflag_match = n_noflag_match + 1;
                    end else begin
                        n_noflag_wrong = n_noflag_wrong + 1;
                    end
                end
            end

        $display("====================================================");
        $display("Case 4: exhaustive 3-bit-flip sweep, 286 combinations, data_in=%b", data_in_ref);
        $display("  error_correct=1, data CORRECT (lucky)         : %0d", n_correct_match);
        $display("  error_correct=1, data WRONG   (MISCORRECTED)  : %0d", n_correct_wrong);
        $display("  double_error=1   (caught, safely rejected)    : %0d", n_double);
        $display("  no flags, data still correct (harmless)       : %0d", n_noflag_match);
        $display("  no flags, data WRONG  (SILENT CORRUPTION)     : %0d", n_noflag_wrong);
        if (first_wrong_i != -1)
            $display("  Example miscorrection: flipping bits {%0d,%0d,%0d} -> error_correct=1 but data_out=%b (expected %b)",
                       first_wrong_i, first_wrong_j, first_wrong_k, first_wrong_data, data_in_ref);
        $display("====================================================");

        $display("--------------------------------------------------");
        $display("TOTAL (Cases 1-3): %0d passed, %0d failed", pass_count, fail_count);
        $display("--------------------------------------------------");

        repeat (4) @(posedge clk);
        $finish;
    end

endmodule