module clk_pll(
    input clk_in1,
    output cpu_clk,
    output timer_clk
);

    assign cpu_clk      = clk_in1;
    assign timer_clk    = clk_in1;
endmodule
