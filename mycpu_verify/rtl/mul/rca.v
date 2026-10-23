module rca #(
    parameter WIDTH = 16 )(
    input [WIDTH-1:0]   op1,
    input [WIDTH-1:0]   op2,
    output [WIDTH-1:0]  sum,
    output              cout
);  

    wire [WIDTH:0] temp;
    assign temp[0] = 1'b0;
    assign cout = temp[WIDTH];

    genvar i;
    generate
        for (i=0; i<WIDTH; i=i+1) begin:RCA
            full_adder full_adder_u (
                .a      (op1[i]),
                .b      (op2[i]),
                .cin    (temp[i]),
                .sum    (sum[i]),
                .cout   (temp[i+1])
            );
        end
    endgenerate


endmodule
