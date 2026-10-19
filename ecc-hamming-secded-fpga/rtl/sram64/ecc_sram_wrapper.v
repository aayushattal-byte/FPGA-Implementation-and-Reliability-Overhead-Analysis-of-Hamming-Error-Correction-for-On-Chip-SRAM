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
