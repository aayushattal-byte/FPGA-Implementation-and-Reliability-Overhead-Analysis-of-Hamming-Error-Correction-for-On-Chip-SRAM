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
