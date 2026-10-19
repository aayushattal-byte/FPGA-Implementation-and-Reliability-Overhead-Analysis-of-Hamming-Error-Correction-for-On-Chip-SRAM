// ============================================================================
// hamming_13_8.v
// Hamming(13,8) SECDED encoder and decoder.
// Signal names/widths match the Lab 2 Functional Specification exactly:
//   Encoder : clk, rst, data_in[7:0], enable, code_out[12:0]
//   Decoder : clk, rst, code_in[12:0], data_out[7:0],
//             error_detect, error_correct, double_error
//
// Bit layout of code_out / code_in (13 bits, index 0..12):
//   idx :  0   1   2   3   4   5   6   7   8   9  10  11  12
//   role:  P1  P2  D0  P4  D1  D2  D3  P8  D4  D5  D6  D7  P13
// (P1,P2,P4,P8 = Hamming parity bits at "positions" 1,2,4,8 in classic
//  1-indexed Hamming numbering; P13 = extra overall-parity bit for SECDED)
// ============================================================================
`timescale 1ns / 1ps

// -----------------------------------------------------------------------
// ECC Encoder
// -----------------------------------------------------------------------
module ecc_encoder (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data_in,
    input  wire       enable,
    output reg  [12:0] code_out
);

    wire d0 = data_in[0];
    wire d1 = data_in[1];
    wire d2 = data_in[2];
    wire d3 = data_in[3];
    wire d4 = data_in[4];
    wire d5 = data_in[5];
    wire d6 = data_in[6];
    wire d7 = data_in[7];

    wire p1 = d0 ^ d1 ^ d3 ^ d4 ^ d6;
    wire p2 = d0 ^ d2 ^ d3 ^ d5 ^ d6;
    wire p4 = d1 ^ d2 ^ d3 ^ d7;
    wire p8 = d4 ^ d5 ^ d6 ^ d7;

    wire [11:0] body = {d7, d6, d5, d4, p8, d3, d2, d1, p4, d0, p2, p1};
    // body[11:0] indices match idx 11..0 above (D7..P1)

    wire p13 = ^body;   // overall even parity over the 12-bit Hamming field

    always @(posedge clk) begin
        if (rst)
            code_out <= 13'd0;
        else if (enable)
            code_out <= {p13, body};
    end

endmodule


// -----------------------------------------------------------------------
// ECC Decoder
// -----------------------------------------------------------------------
module ecc_decoder (
    input  wire        clk,
    input  wire        rst,
    input  wire [12:0] code_in,
    output reg  [7:0]  data_out,
    output reg         error_detect,   // 1 = any error found (single or double)
    output reg         error_correct,  // 1 = a single-bit error was corrected
    output reg         double_error    // 1 = uncorrectable double-bit error
);

    wire [11:0] body = code_in[11:0];
    wire p13_rx      = code_in[12];

    // recompute the 4-bit syndrome (includes each parity bit's own position,
    // matching how the encoder generated it -- syndrome=0 means consistent)
    wire s0 = body[0] ^ body[2] ^ body[4] ^ body[6] ^ body[8] ^ body[10];
    wire s1 = body[1] ^ body[2] ^ body[5] ^ body[6] ^ body[9] ^ body[10];
    wire s2 = body[3] ^ body[4] ^ body[5] ^ body[6] ^ body[11];
    wire s3 = body[7] ^ body[8] ^ body[9] ^ body[10] ^ body[11];

    wire [3:0] syndrome = {s3, s2, s1, s0};      // 0 = no error in the 12-bit field
    wire       overall_check = p13_rx ^ (^body); // 0 = even parity holds over 13 bits

    reg [11:0] corrected;
    reg d_err, s_err, dbl_err;

    always @* begin
        corrected = body;
        d_err = 1'b0;
        s_err = 1'b0;
        dbl_err = 1'b0;

        if (syndrome == 4'd0 && overall_check == 1'b0) begin
            // no error
        end else if (syndrome == 4'd0 && overall_check == 1'b1) begin
            // error only in the overall parity bit itself -- data unaffected
            d_err = 1'b1; s_err = 1'b1;
        end else if (syndrome != 4'd0 && overall_check == 1'b1) begin
            // single-bit error inside the 12-bit field -- flip and fix it
            corrected[syndrome - 1'b1] = ~body[syndrome - 1'b1];
            d_err = 1'b1; s_err = 1'b1;
        end else begin
            // syndrome != 0 and overall_check == 0 -> two-bit error
            d_err = 1'b1; dbl_err = 1'b1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            data_out      <= 8'd0;
            error_detect  <= 1'b0;
            error_correct <= 1'b0;
            double_error  <= 1'b0;
        end else begin
            // extract the 8 data bits back out (idx 2,4,5,6,8,9,10,11 = D0..D7)
            data_out <= {corrected[11], corrected[10], corrected[9], corrected[8],
                         corrected[6],  corrected[5],  corrected[4], corrected[2]};
            error_detect  <= d_err;
            error_correct <= s_err;
            double_error  <= dbl_err;
        end
    end

endmodule
