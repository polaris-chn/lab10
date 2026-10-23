module wallace_tree (

    input wire [63:0] x_psum [0:16],
    output [63:0] result
);

    // level 1
    wire [4:0][63:0] sum_level_1;
    wire [4:0][63:0] cout_level_1;
    genvar i;
    generate 
        for (i=0; i<5; i++) begin
        csa csa_u_1 (
            .op1    (x_psum[3*i]   << (6*i)),
            .op2    (x_psum[3*i+1] << (6*i+2)),
            .op3    (x_psum[3*i+2] << (6*i+4)),
            .sum    (sum_level_1[i]),
            .cout   (cout_level_1[i])
        );
        end
    endgenerate

    // level 2
    wire [3:0][63:0] sum_level_2;
    wire [3:0][63:0] cout_level_2;
    csa csa_u_2_1 (
        .op1    (sum_level_1[0]),
        .op2    (cout_level_1[0]),
        .op3    (sum_level_1[1]),
        .sum    (sum_level_2[0]),
        .cout   (cout_level_2[0])
    );

    csa csa_u_2_2 (
        .op1    (cout_level_1[1]),
        .op2    (sum_level_1[2]),
        .op3    (cout_level_1[2]),
        .sum    (sum_level_2[1]),
        .cout   (cout_level_2[1])
    );

    csa csa_u_2_3 (
        .op1    (sum_level_1[3]),
        .op2    (cout_level_1[3]),
        .op3    (sum_level_1[4]),
        .sum    (sum_level_2[2]),
        .cout   (cout_level_2[2])
    );

    csa csa_u_2_4 (
        .op1    (cout_level_1[4]),
        .op2    (x_psum[15] << 30),
        .op3    (x_psum[16] << 32),
        .sum    (sum_level_2[3]),
        .cout   (cout_level_2[3])
    );
    
    // level 3
    wire [1:0][63:0] sum_level_3;
    wire [1:0][63:0] cout_level_3;
    csa csa_u_3_1 (
        .op1    (sum_level_2[0]),
        .op2    (cout_level_2[0]),
        .op3    (sum_level_2[1]),
        .sum    (sum_level_3[0]),
        .cout   (cout_level_3[0])
    );
    
    csa csa_u_3_2 (
        .op1    (cout_level_2[1]),
        .op2    (sum_level_2[2]),
        .op3    (cout_level_2[2]),
        .sum    (sum_level_3[1]),
        .cout   (cout_level_3[1])
    );

    // level 4
    wire [1:0][63:0] sum_level_4;
    wire [1:0][63:0] cout_level_4;
    csa csa_u_4_1 (
        .op1    (sum_level_3[0]),
        .op2    (cout_level_3[0]),
        .op3    (sum_level_3[1]),
        .sum    (sum_level_4[0]),
        .cout   (cout_level_4[0])
    );

    csa csa_u_4_2 (
        .op1    (cout_level_3[1]),
        .op2    (sum_level_2[3]),
        .op3    (cout_level_2[3]),
        .sum    (sum_level_4[1]),
        .cout   (cout_level_4[1])
    );

    // level 5
    wire [63:0] sum_level_5;
    wire [63:0] cout_level_5;
    csa csa_u_5_1 (
        .op1    (sum_level_4[0]),
        .op2    (cout_level_4[0]),
        .op3    (sum_level_4[1]),
        .sum    (sum_level_5),
        .cout   (cout_level_5)
    );

    // level 6
    wire [63:0] sum_level_6;
    wire [63:0] cout_level_6;
    csa csa_u_6_1 (
        .op1    (sum_level_5),
        .op2    (cout_level_5),
        .op3    (cout_level_4[1]),
        .sum    (sum_level_6),
        .cout   (cout_level_6)
    );

    // level 7, rca
    rca #(
        .WIDTH  (64)
    )   rca_1 (
        .op1    (sum_level_6),
        .op2    (cout_level_6),
        .sum    (result),
        .cout   ()
    );

endmodule
