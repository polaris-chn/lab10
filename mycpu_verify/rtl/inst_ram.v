module inst_ram(
    input               clka,
    input               ena,
    input wire  [3:0]   wea,
    input wire  [17:0]  addra,
    input wire  [31:0]  dina,

    output      [31:0]  douta

);
    
    reg [31:0] i_mem [0:262143];
    reg [31:0] dout;
    always@(posedge clka) begin
        if(ena) begin
            if(wea)
                i_mem[addra]    <= dina;
            else
                dout            <= i_mem[addra];
        end
    end

    assign douta = dout;

endmodule
