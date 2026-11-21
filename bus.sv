
module top (
    input wire clk,
    input wire a_we,
    input wire b_we,
    input wire bus_src,
    output [7:0] bus_out
);
    // reg(clk) rst: bool initial(true) = 1;
    reg rst = 1;

    always @(posedge clk) begin
        rst <= 0;
    end

    bus bus (.clk(clk), .rst(rst), .a_we(a_we), .b_we(b_we), .bus_src(bus_src), .bus_out(bus_out));

endmodule

module bus (
    input wire clk,
    input wire rst,
    input wire a_we,
    input wire b_we,
    input wire bus_src,
    output [7:0] bus_out
);
    reg [7:0] a = 0;
    reg [7:0] b = 0;

    assign bus_out = bus_src ? b : a;

    always @(posedge clk) begin
        if (rst) begin
            a <= 0;
            b <= 0;
        end else if (a_we) begin
            a <= bus_out;
        end else if (b_we) begin
            b <= bus_out; 
        end
    end
endmodule