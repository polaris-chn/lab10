module mult_top (
    input           mul_clk,
    input           reset,
    input           mul,
    input           mul_signed,
    input [31:0]    x,
    input [31:0]    y,
    output [31:0]   result_h,
    output [31:0]   result_l,
    output          complete
);
    wire [33:0] x_ext;
    wire [33:0] y_ext;
    assign x_ext = mul_signed ? {{2{x[31]}}, x} : {{2{1'b0}}, x};
    assign y_ext = mul_signed ? {{2{y[31]}}, y} : {{2{1'b0}}, y};

    reg [1:0] count;
    always@(posedge mul_clk or negedge reset) begin
        if (reset || !mul)
            count   <= 0;
        else if (count==2'd2)
            count   <= 0;
        else
            count   <= count + 1'b1;
    end
    assign complete = (count==2'd2);

    wire [16:0] neg;
    wire [16:0] zero;
    wire [16:0] one;
    wire [16:0] two;
    genvar i;
    generate
        for (i=0; i<17; i=i+1) begin:BOOTH
            if (i==0)
                booth booth_u (
                    .in     ({y_ext[1:0], 1'b0}),
                    .neg    (neg[i]),
                    .zero   (zero[i]),
                    .one    (one[i]),
                    .two    (two[i])
                );
            else
                booth booth_u (
                    .in     (y_ext[i*2+1:i*2-1]),
                    .neg    (neg[i]),
                    .zero   (zero[i]),
                    .one    (one[i]),
                    .two    (two[i])
                );
        end
    endgenerate

        
    wire [16:0][63:0] x_ext_psum;
    genvar j;
    generate
        for (j=0; j<17; j++) begin:PSUM
            psum psum_u (
                .x          (x_ext),
                .neg        (neg[j]),
                .zero       (zero[j]),
                .one        (one[j]),
                .two        (two[j]),
                .x_psum     (x_ext_psum[j])
            );
        end
    endgenerate

    reg [63:0] psum_reg [0:16];
    integer k;
    always@(posedge mul_clk or negedge reset) begin
        if (reset)
            for (k=0; k<17; k=k+1)
                psum_reg[k] <= 64'd0;
        else
            for (k=0; k<17; k=k+1)
                psum_reg[k] <= x_ext_psum[k];
    end

    wire [63:0] result;
    wallace_tree wallace_tree (
       .x_psum      (psum_reg),
       .result      (result)
    );

    assign result_h = result[63:32];
    assign result_l = result[31:0];


endmodule
