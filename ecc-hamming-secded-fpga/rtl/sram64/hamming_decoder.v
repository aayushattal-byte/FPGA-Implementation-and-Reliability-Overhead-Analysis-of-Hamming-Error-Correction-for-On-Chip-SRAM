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
