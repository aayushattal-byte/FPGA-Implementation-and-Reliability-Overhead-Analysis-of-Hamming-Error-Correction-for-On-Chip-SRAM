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
