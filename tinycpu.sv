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
    
    bus bus (.clk(clk), .rst(rst), .a_we(a_we), .b_we(b_we), .bus_src(bus_src));
    assign bus_out = bus.bus_out;

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

typedef enum logic [2:0] { 
    SRC_A, SRC_B, SRC_PC, SRC_INSTR, SRC_RAM, SRC_ALU
 } BusSrc;

typedef struct packed {
    logic a_we;
    logic b_we;
    // bus src: a, b, pc, instr, ram, alu, 
    BusSrc bus_src;
    
} Control;


module datapath (
    input wire clk,
    input wire rst,
    Control c,
    output [15:0] bus
);

    reg [15:0] a = 0;  
    reg [15:0] b = 0;  

    // pc
    reg [11:0] pc = 0;
    
    // instr
    reg [15:0] instr = 0;
    
    // mar
    reg [11:0] mar = 0;
    
    // ram

    // alu
    reg [15:0] u = 0;
    reg [15:0] v = 0;
    
    alu alu (.u(u), .v(v));

    always @(posedge clk) begin
        a = 
    end

    assign bus = 
    
endmodule

module alu (
    input wire op,
    input [15:0] u,
    input [15:0] v,
    output [15:0] res
);
    assign res = op ? {u * v} : {u + v};

endmodule


