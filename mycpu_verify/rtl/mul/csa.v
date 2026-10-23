// 3-2 compressor, carry save adder


module csa #(
    WIDTH = 64
)(
    input [WIDTH-1:0] op1, op2, op3,
    output [WIDTH-1:0] sum, cout
);
    
    wire [WIDTH-1:0] cout_tmp;
    genvar i;
    generate 
        for (i=0; i<WIDTH; i++) begin
            full_adder full_adder_u (
                .a      (op1[i]),
                .b      (op2[i]),
                .cin    (op3[i]),
                .sum    (sum[i]),
                .cout   (cout_tmp[i])
            );
        end
    endgenerate

    assign cout = {cout_tmp[WIDTH-2:0], 1'b0};

endmodule
