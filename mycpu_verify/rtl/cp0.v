`include "mycpu.h"

module cp0 (
    input           clk,
    input           reset,
    input           inst_mfc0,
    input           mtc0_we,
    input           excp,
    input           eret_flush,
    input           bd,
    input   [4:0]   ex_code_in,
    input   [31:0]  ex_pc,
    input   [4:0]   cp0_addr,
    input   [2:0]   sel,
    input   [31:0]  wr_data,
    input   [5:0]   ext_int_in,
    input           fs_adel_exp,

    output  [31:0]  cp0_rd_data,
    output          has_intr

);

    // exception判断
    wire    [4:0]   ex_code;
    // 指令例外优先于中断
    wire        inst_excp_code = (ex_code_in != 5'h1f);
    assign          ex_code =   inst_excp_code ? ex_code_in :
                                (has_intr ? `EXP_INT : ex_code_in);

    // cp0 写操作
    // reg status
    wire status_bev;
    assign status_bev = 1'b1;

    reg [7:0] status_im;
    always@(posedge clk) begin
        if (mtc0_we && cp0_addr==`CR_STATUS)
            status_im <= wr_data[15:8];
    end

    reg status_exl;
    always@(posedge clk) begin
        if (reset)
            status_exl <= 1'b0;
        else if (excp)
            status_exl <= 1'b1;
        else if (eret_flush)
            status_exl <= 1'b0;
        else if (mtc0_we && cp0_addr==`CR_STATUS)
            status_exl <= wr_data[1];
    end

    reg status_ie;
    always@(posedge clk) begin
        if (reset)
            status_ie <= 1'b0;
        else if (mtc0_we && cp0_addr==`CR_STATUS)
            status_ie <= wr_data[0];
    end


    // reg cause
    wire count_eq_compare;
    reg cause_bd;
    always@(posedge clk) begin
        if (reset)
            cause_bd <= 1'b0;
        else if (excp && !status_exl)
            cause_bd <= bd;
    end

    reg cause_ti;
    always@(posedge clk) begin
        if (reset)
            cause_ti <= 1'b0;
        else if (mtc0_we && cp0_addr==`CR_COMPARE)
            cause_ti <= 1'b0;
        else if (count_eq_compare)
            cause_ti <= 1'b1;
        /*
        else
            cause_ti <= 1'b0;
        */
    end

    reg [7:0] cause_ip;
    always@(posedge clk) begin
        if (reset)
            cause_ip        <= 8'h00;
        else if (mtc0_we && cp0_addr==`CR_CAUSE)
            cause_ip[1:0]   <= wr_data[9:8];
        else begin
            cause_ip[7]     <= ext_int_in[5] | cause_ti;
            cause_ip[6:2]   <= ext_int_in[4:0];
        end
    end

    reg [4:0] cause_excode;
    always@(posedge clk) begin
        if (reset)
            cause_excode    <= 5'd0;
        else if (excp)
            cause_excode    <= ex_code;
    end

    // reg epc
    reg [31:0]  epc;
    always@(posedge clk) begin
        if (excp && !status_exl)
            epc             <= bd ? ex_pc-3'h4 : ex_pc;
        else if (mtc0_we && cp0_addr==`CR_EPC)
            epc             <= wr_data;
    end

    // reg badvaddr
    reg [31:0] badvaddr;
    always@(posedge clk) begin
        if (excp && cp0_addr==`CR_BADVADDR)
            badvaddr        <= wr_data;
    end

    // reg count
    reg [31:0]  count;
    reg         tick;
    always@(posedge clk) begin
        if (reset) begin
            tick            <= 1'b0;
            count           <= 32'd0;
        end
        else begin
            tick            <= ~tick;

            if (mtc0_we && cp0_addr==`CR_COUNT) begin
                count           <= wr_data;
            end
            else if (tick)
                count           <= count + 1'b1;
            if (count_eq_compare) begin
            end
        end
    end


    // reg compare
    reg [31:0]  compare;
    always@(posedge clk) begin
        if (reset)
            compare         <= 32'd0;
        else if (mtc0_we && cp0_addr==`CR_COMPARE)
            compare         <= wr_data;
    end

    assign count_eq_compare = (count == compare);



    // cp0 读操作
    reg [31:0] rd_data;
    always@(*) begin
        if (inst_mfc0)
            case (cp0_addr)
                `CR_BADVADDR: rd_data = badvaddr;
                `CR_COUNT   : rd_data = count;
                `CR_COMPARE : rd_data = compare;
                `CR_STATUS  : rd_data = {9'h000, status_bev, 6'h00, status_im, 6'h00, status_exl, status_ie};
                `CR_CAUSE   : rd_data = {cause_bd, cause_ti, 14'h0000, cause_ip, 1'b0, cause_excode, 2'h0};
                `CR_EPC     : rd_data = epc;
                default : rd_data = 32'd0; 
            endcase
        else
            rd_data = 32'd0;
    end

    assign  has_intr    =   ((cause_ip & status_im)!=8'h00) && status_ie==1'b1 && status_exl==1'b0;

    assign cp0_rd_data  =   eret_flush ? epc : rd_data;


endmodule
