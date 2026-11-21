
typedef enum logic [2:0] { 
    SRC_A, SRC_B, SRC_PC, SRC_INSTR, SRC_RAM, SRC_ALU
 } BusSrc;

typedef struct packed {
    logic a_we;
    logic b_we;
    logic pc_jmp;
    logic pc_inc;
    logic instr_we;
    logic mar_we;
    logic mar_inc;
    logic u_we;
    logic v_we;
    logic alu_op;

    logic ram_hi_we;
    logic ram_lo_we;

    logic mem_hi_we;
    logic step_rst;
    logic hlt;
    // bus src: a, b, pc, instr, ram, alu, 
    BusSrc bus_src;
    
} Control;

module tinycpu (
    input wire clk
);
    // reg(clk) rst: bool initial(true) = 1;
    reg rst = 1;

    always @(posedge clk) begin
        rst <= 0;
    end

    logic [15:0] bus;
    logic [3:0] opcode;
    Control c;
    datapath datapath (.clk(clk), .c(c), .bus(bus), .opcode(opcode));
    controller controller (.clk(clk), .rst(rst), .opcode(opcode), .cout(c));

endmodule



module datapath (
    input wire clk,
    // input wire rst,
    input Control c,
    output logic [15:0] bus,
    output logic [3:0] opcode
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
    logic [7:0] ram [0:4095];
    logic [7:0] ram_q;
    reg [7:0] mem_hi = 0;

    // alu
    reg [15:0] u = 0;
    reg [15:0] v = 0;
    
    logic [15:0] alu_out;
    alu alu (.u(u), .v(v), .op(c.alu_op), .res(alu_out));

    always @(posedge clk) begin
        a <= c.a_we ? bus : a;
        b <= c.b_we ? bus : b;
        instr <= c.instr_we ? bus : instr;
        u <= c.u_we ? bus : u;
        v <= c.v_we ? bus : v;
        
        if (c.pc_jmp) begin
            pc <= bus[11:0]; 
        end else if (c.pc_inc) begin
            pc <= pc + 2; // word size is 2 bytes 
        end
        
        if (c.mar_we) begin
            mar <= bus[11:0]; 
        end else if (c.mar_inc) begin
            mar <= mar + 1; // the ram is byte addressed 
        end

        ram_q <= ram[mar];
        mem_hi <= c.mem_hi_we ? ram[mar] : mem_hi;

        if (c.ram_hi_we) begin
            ram[mar] <= bus[15:8];
        end else if (c.ram_lo_we) begin
            ram[mar] <= bus[7:0];
        end
    end

    always_comb begin case (c.bus_src)
        SRC_A: bus = a;
        SRC_B: bus = b;
        SRC_PC: bus = {4'b0, pc};
        SRC_INSTR: bus = {4'b0, instr[11:0]}; // erase opcode from instr when putting on bus
        SRC_RAM: bus = {mem_hi, ram_q};
        SRC_ALU: bus = alu_out;
    endcase
    end
    assign opcode = instr[15:12];

endmodule

module alu (
    input [15:0] u,
    input [15:0] v,
    input wire op,
    output [15:0] res
);
    assign res = op ? {u * v} : {u + v};

endmodule


module controller (
    input wire clk,
    input wire rst,
    // input Control c,
    input [3:0] opcode,
    output Control cout
);
    reg [3:0] step = 0;

    always @(posedge clk) begin
        step <= (rst | cout.step_rst) ? 0 : step + 1;
    end
    /*
     fetch is 
    pc out, mar in
    mem_hi_we, pc_inc, mar_inc,
    _ nothing (wait for ram_q to latch)
    ram_out, instr_we,

    */
    // if step 
    Control pc_to_mar, advance_ram, idle, latch_instr, steprst;
    logic [0:3][$bits(cout)-1:0] fetch_steps;

    always_comb begin 
        pc_to_mar = '0;
        pc_to_mar.bus_src = SRC_PC;
        pc_to_mar.mar_we = 1;

        advance_ram = 0;
        advance_ram.mem_hi_we = 1;
        advance_ram.mar_inc = 1;
        advance_ram.pc_inc = 1;

        idle = 0;

        latch_instr = 0;
        latch_instr.bus_src = SRC_RAM;
        latch_instr.instr_we = 1;
        
        steprst = 0;
        steprst.step_rst = 1;

        fetch_steps = {pc_to_mar, advance_ram, idle, latch_instr};
        cout = '0;

        if (step < $size(fetch_steps)) begin
            cout = fetch_steps[step];
        end else if (opcode == 'hF) begin
            cout.hlt = 1;
        end
    end
    
endmodule