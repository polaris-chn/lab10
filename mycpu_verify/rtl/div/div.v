module div (
    input           div_clk,
    input           reset,
    input           div,
    input           div_signed,
    input   [31:0]  x,
    input   [31:0]  y,
    output  [31:0]  s,
    output  [31:0]  r,
    output          complete
);
    
    wire [31:0] abs_x;
    wire [31:0] abs_y;
    assign abs_x = (x[31] && div_signed) ? ~x+1'b1 : x;
    assign abs_y = (y[31] && div_signed) ? ~y+1'b1 : y;

    reg [5:0] count;
    always@(posedge div_clk or negedge reset) begin
        if (reset || !div)
            count <= 0;
        else if (count==6'd32)
            count <= 0;
        else
            count <= count + 1'b1;
    end
    assign complete = (count==6'd32);
    
    // s_tmp: 商；r_tmp: 余数
    reg [31:0] s_tmp;
    reg [31:0] r_tmp;
    wire [32:0] sub_out;
    wire [31:0] mux_out;
    always@(posedge div_clk or negedge reset) begin 
        if (reset || !div) begin
            s_tmp   <= 32'h0000_0000;
            r_tmp   <= 32'h0000_0000;
        end

        else if (div) begin
            s_tmp   <= {s_tmp[30:0], ~sub_out[32]};
            r_tmp   <= mux_out;
        end

    end

    assign sub_out = {r_tmp, abs_x[31-count]} - {1'b0, abs_y};
    assign mux_out = sub_out[32] ? {r_tmp[30:0], abs_x[31-count]} : sub_out[31:0];

    
    assign s = (div_signed && ((x[31]==1'b0 && y[31]==1'b1) || (x[31]==1'b1 && y[31]==1'b0))) ?
                ~s_tmp+1'b1 : s_tmp;
    assign r = (div_signed && ((x[31]==1'b1 && y[31]==1'b0) || (x[31]==1'b1 && y[31]==1'b1))) ?
                ~r_tmp+1'b1 : r_tmp;

endmodule
