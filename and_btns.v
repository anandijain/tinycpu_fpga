module top (
    
    input wire l_btn,
    input wire r_btn,
    output [5:0] led_n
);

    assign led_n = {6{~(l_btn & r_btn)}};
endmodule