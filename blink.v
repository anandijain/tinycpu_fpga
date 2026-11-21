module top (
    input wire clk,
    output wire led_n // _n suffix indicates an active lo signal
);
    reg [23:0] ctr = 0;

    always @(posedge clk) begin
        ctr <= ctr + 1;
    end
    assign led_n = ~ctr[23];
endmodule