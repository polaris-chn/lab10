`include "mycpu.h"

module wb_stage(
    input                           clk             ,
    input                           reset           ,
    //allowin
    output                          ws_allowin      ,
    //from ms
    input                           ms_to_ws_valid  ,
    input  [`MS_TO_WS_BUS_WD -1:0]  ms_to_ws_bus    ,
    //to rf: for write back
    output [`WS_TO_RF_BUS_WD -1:0]  ws_to_rf_bus    ,
    output                          ws_forward_excp   ,         // 传到if级，有例外发生，则跳转到指定pc地址
    output                          ws_forward_eret ,
    output                          has_intr_out    ,       // timer interrupt signal to IF
    output [31:0]                   ws_to_fs_pc     ,
    //trace debug interface
    output [31:0] debug_wb_pc                       ,
    output [ 3:0] debug_wb_rf_wen                   ,
    output [ 4:0] debug_wb_rf_wnum                  ,
    output [31:0] debug_wb_rf_wdata                 ,


    //output [4:0] WB_wdest
    output [`WS_TO_DS_FORWARD_BUS -1:0] ws_to_ds_forward_bus
);

    // 接受从前级传来的信号
    reg [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus_r;
    wire        ws_gr_we;
    wire [ 4:0] ws_dest;
    wire [31:0] ws_final_result;
    wire [31:0] ws_pc;
    wire        ws_inst_mfc0;
    wire        ws_inst_mtc0;
    wire [2:0]  ws_sel;
    wire [4:0]  ws_excode;
    wire [5:0]  ws_intr;
    wire [4:0]  ws_cp0_addr;
    wire        ws_inst_eret;
    wire [31:0] fs_to_ws_epc;
    wire        fs_to_ws_adel;
    wire        ws_bd_slot;
    assign {ws_bd_slot          ,
            fs_to_ws_adel       ,
            fs_to_ws_epc        ,
            ws_inst_eret        ,
            ws_cp0_addr         ,
            ws_intr             ,
            ws_excode           ,
            ws_inst_mfc0        ,
            ws_inst_mtc0        ,
            ws_sel              ,
            ws_gr_we            ,  //69:69
            ws_dest             ,  //68:64
            ws_final_result     ,  //63:32
            ws_pc             //31:0
           } = ms_to_ws_bus_r;

    // 流水线逐级互锁 
    reg         ws_valid;
    wire        ws_ready_go;
    assign ws_ready_go = 1'b1;
    assign ws_allowin  = !ws_valid || ws_ready_go;
    always @(posedge clk) begin
        if (reset) begin
            ws_valid <= 1'b0;
        end
        else if (ws_allowin) begin
            ws_valid <= ms_to_ws_valid;
        end

        if (ms_to_ws_valid && ws_allowin) begin
            ms_to_ws_bus_r <= ms_to_ws_bus;
        end
    end


    // cp0 信号
    wire [31:0] cp0_rd_data;
    wire        ws_has_intr;
    wire        ws_take_intr;

    // 中断挂起：仅在 has_intr 上升沿置位，避免电平期间反复进中断
    reg         intr_pending;
    reg         has_intr_r;
    wire        has_intr_rise = ws_has_intr && !has_intr_r;
    always @(posedge clk) begin
        if (reset) begin
            intr_pending <= 1'b0;
            has_intr_r   <= 1'b0;
        end
        else begin
            has_intr_r <= ws_has_intr;
            if (ws_take_intr)
                intr_pending <= 1'b0;
            else if (has_intr_rise)
                intr_pending <= 1'b1;
        end
    end

    wire        eret_epc_adel;
    wire        ws_excp;
    wire        ws_mtc0_we;
    wire [4:0]  cp0_addr;
    wire [31:0] cp0_wr_data;
    wire [31:0] ex_pc;
    wire [4:0]  ex_code;
    wire        ws_bd;

    assign      eret_epc_adel   =   ws_inst_eret && cp0_rd_data[1:0]!=2'b00;

    assign      ws_inst_excp    =   ( ws_excode==`EXP_ADEL    || ws_excode ==`EXP_ADES    ||
                                      ws_excode==`EXP_SYS     || ws_excode==`EXP_BP       ||
                                      ws_excode ==`EXP_RI     || ws_excode==`EXP_OV       ||
                                      eret_epc_adel                                           );

    // 指令例外优先于中断；中断不在 mtc0 写 CP0 的同拍响应
    assign      ws_take_intr    =   intr_pending && ws_valid && !ws_inst_mtc0 && !ws_inst_excp;

    assign      ws_excp = ws_inst_excp || ws_take_intr;

    assign      ws_mtc0_we = ws_valid && ws_inst_mtc0 && !ws_excp;

    assign      cp0_addr    =   (ex_code==`EXP_ADEL || ex_code==`EXP_ADES)      ?   `CR_BADVADDR    :
                                ws_inst_mfc0                                    ?   ws_cp0_addr     :   ws_dest;

    assign      cp0_wr_data =   fs_to_ws_adel   ?   fs_to_ws_epc    :
                                eret_epc_adel   ?   cp0_rd_data     :
                                                    ws_final_result ;

    assign      ex_pc       =   fs_to_ws_adel   ?   fs_to_ws_epc    :
                                eret_epc_adel   ?   cp0_rd_data     :
                                                    ws_pc           ;

    assign      ex_code     =   eret_epc_adel       ?   `EXP_ADEL       :   ws_excode;

    assign      ws_bd       =   ws_bd_slot  && ~fs_to_ws_adel;

    cp0 cp0_uut (
        .clk            (clk),
        .reset          (reset),
        .inst_mfc0      (ws_inst_mfc0),
        .mtc0_we        (ws_mtc0_we),
        .excp           (ws_excp),
        .eret_flush     (ws_inst_eret),
        .bd             (ws_bd),
        .ex_code_in     (ex_code),
        .ex_pc          (ex_pc),
        .cp0_addr       (cp0_addr),
        .sel            (ws_sel),
        .wr_data        (cp0_wr_data),
        .ext_int_in     (ws_intr),
        .fs_adel_exp    (fs_to_ws_adel),
        .cp0_rd_data    (cp0_rd_data),
        .has_intr       (ws_has_intr)
    );

    // 写回到regfile的使能，地址，数据
    wire        rf_we;
    wire [4 :0] rf_waddr;
    wire [31:0] rf_wdata;
    assign rf_we    = ~ws_forward_excp && ws_gr_we && ws_valid;
    assign rf_waddr = ws_dest;
    assign rf_wdata = ws_inst_mfc0 ? cp0_rd_data : ws_final_result;
    assign ws_to_rf_bus = {rf_we   ,  //37:37
                           rf_waddr,  //36:32
                           rf_wdata   //31:0
                          };


    // 写回到if级的例外发生信号
    assign  ws_forward_excp     =   ws_excp && ws_valid;
    assign  ws_forward_eret     =   ws_inst_eret && ws_valid;
    assign  has_intr_out        =   ws_take_intr;
    assign  ws_to_fs_pc         =   cp0_rd_data;


    // 前递通路
	assign dest_zero            = (ws_dest == 5'b0); 
	assign forward_enable       = ws_gr_we & ~dest_zero & ws_valid;
	assign dep_need_stall       = !(ws_valid && ws_ready_go && ~ws_inst_mfc0); 
	assign ws_to_ds_forward_bus = { dep_need_stall ,  //38:38
                               	    forward_enable ,  	 //37:37
                               	    ws_dest        ,  	 //36:32
                               	    ws_final_result};      //31:0};

    // debug info generate
    // 包括这条指令的pc，写regfile使能，写regfile地址，写regfile数据
    // 和产生的golden_trace.txt进行比对，完全相同则通过
    assign debug_wb_pc       = ws_pc;
    assign debug_wb_rf_wen   = {4{rf_we}};
    assign debug_wb_rf_wnum  = ws_dest;
    assign debug_wb_rf_wdata = ws_inst_mfc0 ? cp0_rd_data : ws_final_result;

endmodule
