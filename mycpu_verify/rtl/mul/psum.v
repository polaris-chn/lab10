// generate partial sum



module psum (
    input [33:0] x,
    input neg,
    input zero,
    input one,
    input two,
    output [63:0] x_psum
);

    reg [63:0] psum_tmp;
    always@(*) begin
        if (zero)
            psum_tmp = 64'd0;
        else if (one)
            psum_tmp = {{30{x[33]}}, x};
        else if (two)
            psum_tmp = {{29{x[33]}}, x, 1'b0};
    end

    assign x_psum = (neg==1'b1) ? (~psum_tmp+1'b1) : psum_tmp;

endmodule
