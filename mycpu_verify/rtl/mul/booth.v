// radix-4 booth encode


module booth (
    input [2:0] in,
    output neg,
    output zero,
    output one,
    output two
);

    assign neg  = in[2];
    assign zero = (in==3'b000) || (in==3'b111);
    assign two  = (in==3'b011) || (in==3'b100);
    assign one  = !zero && !two;

endmodule
