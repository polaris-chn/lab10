module data_ram(
    input               clka,
    input               ena,
    input wire  [3:0]   wea,
    input wire  [15:0]  addra,
    input wire  [31:0]  dina,
    
    output      [31:0]  douta
);

    reg [31:0] d_mem [0:65535];
    reg [31:0] dout;
    always@(posedge clka) begin
        if(ena) begin
            if(wea) begin
                case(wea[0])
                    1'b0 : d_mem[addra][7:0]    <= d_mem[addra][7:0];
                    1'b1 : d_mem[addra][7:0]    <= dina[7:0];
                    default: d_mem[addra][7:0]  <= 8'h00;
                endcase

                case(wea[1])
                    1'b0 : d_mem[addra][15:8]    <= d_mem[addra][15:8];
                    1'b1 : d_mem[addra][15:8]    <= dina[15:8];
                    default: d_mem[addra][15:8]  <= 8'h00;
                endcase

                case(wea[2])
                    1'b0 : d_mem[addra][23:16]    <= d_mem[addra][23:16];
                    1'b1 : d_mem[addra][23:16]    <= dina[23:16];
                    default: d_mem[addra][23:16]  <= 8'h00;
                endcase

                case(wea[3])
                    1'b0 : d_mem[addra][31:24]    <= d_mem[addra][31:24];
                    1'b1 : d_mem[addra][31:24]    <= dina[31:24];
                    default: d_mem[addra][31:24]  <= 8'h00;
                endcase
            end

            else
                dout            <= d_mem[addra];
        end
    end

    assign douta = dout;

endmodule
