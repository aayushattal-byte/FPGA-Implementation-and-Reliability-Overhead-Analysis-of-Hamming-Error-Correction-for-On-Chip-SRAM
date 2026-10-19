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
