
typedef enum logic [2:0] { 
    SRC_A, SRC_B, SRC_PC, SRC_INSTR, SRC_RAM, SRC_ALU
 } BusSrc;


typedef enum logic [2:0] { 
    ALU_NOP, ALU_ADD, ALU_MUL, ALU_SUB, ALU_AND, ALU_SHR
} AluOp;

typedef enum logic [3:0] { 
    NOP, // 0
    LDA, // 1
    ADD, // 2
    SUB, // 3
    STA, // 4
    LDI, // 5
    JMP, // 6
    JZ, // 7
    MUL, // 8
    LDB, // 9
    JEQ, // 10
    AND, // 11
    SHR, // 12
    CALL, // 13
    RET, // 14
    HLT // 15
} IsaOp;

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
    AluOp alu_op;

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
    input AluOp op,
    output [15:0] res
);

    // assign res = op ? {u * v} : {u + v};
    always_comb begin case (op)
        ALU_NOP: res = 0;
        ALU_ADD: res = u+v;
        ALU_MUL: res = u*v;
        ALU_SUB: res = u-v;
        ALU_AND: res = u&v;
        ALU_SHR: res = u>>v;
    endcase
    end
endmodule



module controller (
    input wire clk,
    input wire rst,
    // input Control c,
    input [3:0] opcode,
    output Control cout
);
    reg [3:0] step = 0;

    always_ff @(posedge clk) begin
        if (rst || cout.step_rst)
            step <= '0;
        else if (!cout.hlt)
            step <= step + 1'b1;
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

    logic [0:0][$bits(cout)-1:0] nop_steps;
    logic [0:4][$bits(cout)-1:0] lda_steps;

    Control instr_to_mar, ram_to_a, ram_to_v;

    Control a_to_u, mem_hi_we_mar_inc, add_alu_into_a;
    logic [0:6][$bits(cout)-1:0] add_steps;
    
    Control sub_alu_into_a;
    logic [0:6][$bits(cout)-1:0] sub_steps;

    logic [0:4][$bits(cout)-1:0] sta_steps;
    Control a_to_hi_ram, a_to_low_ram, mar_inc;

    logic [0:1][$bits(cout)-1:0] ldi_steps;
    Control instr_to_a;

    logic [0:1][$bits(cout)-1:0] jmp_steps;
    Control instr_to_pc;

    logic [0:1][$bits(cout)-1:0] jz_steps;
    logic [0:6][$bits(cout)-1:0] mul_steps;
    Control mul_alu_into_a;

    logic [0:4][$bits(cout)-1:0] ldb_steps;
    Control ram_to_b;

    logic [0:1][$bits(cout)-1:0] jeq_steps;
    logic [0:6][$bits(cout)-1:0] and_steps;
    
    Control and_alu_into_a;
    logic [0:6][$bits(cout)-1:0] shr_steps;
    Control shr_alu_into_a;
    logic [0:0][$bits(cout)-1:0] call_steps;
    logic [0:0][$bits(cout)-1:0] ret_steps;
    logic [0:1][$bits(cout)-1:0] hlt_steps;
    Control hltc;

    always_comb begin 
        // fetch
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

        // nop steps
        nop_steps = {steprst};

        // lda_steps
        instr_to_mar = 0;
        instr_to_mar.bus_src = SRC_INSTR;
        instr_to_mar.mar_we = 1;

        ram_to_a = 0;
        ram_to_a.bus_src = SRC_RAM;
        ram_to_a.a_we = 1;

        mem_hi_we_mar_inc = 0;
        mem_hi_we_mar_inc.mem_hi_we = 1;
        mem_hi_we_mar_inc.mar_inc = 1;

        lda_steps = {instr_to_mar, mem_hi_we_mar_inc, idle, ram_to_a, steprst};

        // add steps
        // add addr:
        // src_a, u_we
        // instr_src, mar_in, 
        // ram_out, v in
        // alu_op = 0, alu_out, a_in
        a_to_u = 0;
        a_to_u.bus_src = SRC_A;
        a_to_u.u_we = 1;

        ram_to_v = 0;
        ram_to_v.bus_src = SRC_RAM;
        ram_to_v.v_we = 1;

        add_alu_into_a = 0;
        add_alu_into_a.alu_op = ALU_ADD;
        add_alu_into_a.bus_src = SRC_ALU;
        add_alu_into_a.a_we = 1;
        
        add_steps = {a_to_u, instr_to_mar, mem_hi_we_mar_inc, idle, ram_to_v, add_alu_into_a, steprst};

        // sub_steps 
        sub_alu_into_a = 0;
        sub_alu_into_a.alu_op = ALU_SUB;
        sub_alu_into_a.bus_src = SRC_ALU;
        sub_alu_into_a.a_we = 1;
        
        sub_steps = {a_to_u, instr_to_mar, mem_hi_we_mar_inc, idle, ram_to_v, sub_alu_into_a, steprst};

        // sta_steps
        /*
        a->bus->ram
        
        */
        a_to_hi_ram = 0;
        a_to_hi_ram.bus_src = SRC_A;
        a_to_hi_ram.ram_hi_we = 1;
        
        mar_inc = 0;
        mar_inc.mar_inc = 1;

        a_to_low_ram = 0;
        a_to_low_ram.bus_src = SRC_A;
        a_to_low_ram.ram_lo_we = 1;
        
        sta_steps = {instr_to_mar, a_to_hi_ram, mar_inc, a_to_low_ram, steprst};

        instr_to_a = 0;
        instr_to_a.bus_src = SRC_INSTR;
        instr_to_a.a_we = 1;
        ldi_steps = {instr_to_a, steprst};
        
        instr_to_pc = 0;
        instr_to_pc.bus_src = SRC_INSTR;
        instr_to_pc.pc_jmp = 1;
        
        jmp_steps = {instr_to_pc, steprst};

        // todo
        jz_steps = jmp_steps;

        mul_alu_into_a = 0;
        mul_alu_into_a.alu_op = ALU_MUL;
        mul_alu_into_a.bus_src = SRC_ALU;
        mul_alu_into_a.a_we = 1;

        mul_steps = {a_to_u, instr_to_mar, mem_hi_we_mar_inc, idle, ram_to_v, mul_alu_into_a, steprst};


        ram_to_b = 0;
        ram_to_b.bus_src = SRC_RAM;
        ram_to_b.b_we = 1;

        ldb_steps = {instr_to_mar, mem_hi_we_mar_inc, idle, ram_to_b, steprst};

        
        // todo
        jeq_steps = jmp_steps;

        and_alu_into_a = 0;
        and_alu_into_a.alu_op = ALU_AND;
        and_alu_into_a.bus_src = SRC_ALU;
        and_alu_into_a.a_we = 1;

        and_steps = {a_to_u, instr_to_mar, mem_hi_we_mar_inc, idle, ram_to_v, and_alu_into_a, steprst};

        shr_alu_into_a = 0;
        shr_alu_into_a.alu_op = ALU_SHR;
        shr_alu_into_a.bus_src = SRC_ALU;
        shr_alu_into_a.a_we = 1;
        shr_steps = {a_to_u, instr_to_mar, mem_hi_we_mar_inc, idle, ram_to_v, shr_alu_into_a, steprst};

        // todo
        call_steps = {steprst};
        ret_steps = {steprst};

        hltc = 0;
        hltc.hlt = 1;
        hlt_steps = {hltc, steprst};
        cout = '0;

        if (step < $size(fetch_steps)) begin
            cout = fetch_steps[step];
        end else begin
            int unsigned i;
            i = int'(step) - $size(fetch_steps);

            case (opcode)
                NOP: cout = steprst;
                LDA: cout = lda_steps[i];
                ADD: cout = add_steps[i];
                SUB: cout = sub_steps[i];
                STA: cout = sta_steps[i];
                LDI: cout = ldi_steps[i];
                JMP: cout = jmp_steps[i];
                JZ: cout  = jz_steps[i];
                MUL: cout = mul_steps[i];
                LDB: cout = ldb_steps[i];
                JEQ: cout = jeq_steps[i];
                AND: cout = and_steps[i];
                SHR: cout = shr_steps[i];
                CALL: cout = call_steps[i];
                RET: cout = ret_steps[i];
                HLT: cout = hltc;
                default: cout = steprst;
            endcase

        end
    end
    
endmodule