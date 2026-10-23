`include "mycpu.h"

module mem_stage(
    input                          clk           ,
    input                          reset         ,
    //allowin
    input                          ws_allowin    ,
    output                         ms_allowin    ,
    //from es
    input                          es_to_ms_valid,
    input                          es_to_ms_wants,
    input                          es_incoming_mem,
    input  [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus  ,
    //to ws
    output                         ms_to_ws_valid,
    output [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus  ,


    //from data-sram
    input  [31                 :0]  data_sram_rdata     ,
    input                           data_sram_addr_ok   ,
    input                           data_sram_data_ok   ,
   

    input                           ws_to_ms_excp,
    input                           ws_to_ms_eret,

    //output [4:0] MEM_wdest
    output [`MS_TO_DS_FORWARD_BUS -1:0] ms_to_ds_forward_bus,
    output                          ms_to_es_excp,
    output                          ms_to_es_eret,
    output                          ms_to_es_handoff
);

    // receive data from former stage
    wire [6:0]                  ms_res_from_mem;
    wire                        ms_gr_we;
    wire [ 4:0]                 ms_dest;
    wire [31:0]                 ms_alu_result;
    wire [31:0]                 ms_pc;
    wire [31:0]                 ms_hi;
    wire [31:0]                 ms_lo;
    wire [31:0]                 ms_alu_src1;
    wire                        ms_inst_mtlo;
    wire                        ms_inst_mthi;
    wire                        ms_inst_mflo;
    wire                        ms_inst_mfhi;
    wire [3:0]                  ms_alu_op;
    wire [31:0]                 ms_rt_value;
    wire                        ms_inst_mfc0;
    wire                        ms_inst_mtc0;
    wire [2:0]                  ms_sel;
    wire [4:0]                  es_to_ms_excode;
    wire [5:0]                  ms_intr;
    wire [3:0]                  ms_ade_exp;
    wire [4:0]                  ms_cp0_addr;
    wire                        ms_inst_eret;
    wire [31:0]                 fs_to_ms_epc;
    wire                        fs_to_ms_adel;
    wire                        ms_bd_slot;
    reg  [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus_r;
    reg                         ms_valid;
    assign {ms_bd_slot          ,
            fs_to_ms_adel       ,
            fs_to_ms_epc        ,
            ms_inst_eret        ,
            ms_cp0_addr         ,
            ms_ade_exp          ,
            ms_intr             ,
            es_to_ms_excode     ,
            ms_inst_mfc0        ,
            ms_inst_mtc0        ,
            ms_sel              ,
            ms_rt_value         ,
            ms_inst_mfhi        ,  //170:170
            ms_inst_mflo        ,  //169:169
            ms_inst_mthi        ,  //168:168
            ms_inst_mtlo        ,  //167:167
            ms_alu_src1         ,  //135:166
            ms_res_from_mem     ,  //70:76 标志信号，代表load指令，最终数据从mem级得到
            ms_gr_we            ,  //69:69
            ms_dest             ,  //68:64
            ms_alu_result       ,  //63:32
            ms_pc             //31:0
           } = {es_to_ms_bus_r[272:181], es_to_ms_bus_r[176:141], es_to_ms_bus_r[76:0]};

    assign {ms_alu_op       ,
            ms_lo           ,
            ms_hi           } = {es_to_ms_bus_r[180:177], es_to_ms_bus_r[140:77]};

    reg [31:0]  hi;
    reg [31:0]  lo;
    always@(posedge clk) begin
        if (reset) begin
            hi  <= 32'd0;
            lo  <= 32'd0;
        end
        // HI/LO 更新必须以 ms_valid 为前提: 指令离开 MEM 级后
        // es_to_ms_bus_r 会残留该指令的 ms_alu_op/ms_hi/ms_lo 等字段,
        // 若不屏蔽，一旦例外/eret 随后离开 WB 使 ws_to_ms_excp 等门控
        // 放开，残留数据会错误地再次更新 HI/LO。与 ms_to_es_* 同类问题。
        else if (ms_valid && |ms_alu_op && ~ws_to_ms_excp && ~ws_to_ms_eret && ~ms_to_es_excp && ~ms_to_es_eret) begin
            hi  <= ms_hi;
            lo  <= ms_lo;
        end
        else if (ms_valid && ms_inst_mthi && ~ws_to_ms_excp && ~ws_to_ms_eret)
            hi  <= ms_alu_src1;
        else if (ms_valid && ms_inst_mtlo && ~ws_to_ms_excp && ~ws_to_ms_eret)
            lo  <= ms_alu_src1;
    end

    wire [31:0] hi_to_rf;
    wire [31:0] lo_to_rf;
    assign      hi_to_rf    = ms_inst_mfhi ? hi : 32'd0;
    assign      lo_to_rf    = ms_inst_mflo ? lo : 32'd0;

    // exception 处理
    wire    [4:0]   ms_excode;
    wire    [4:0]   ms_exp;
    assign          ms_excode   =   (ms_ade_exp[3] && ms_alu_result[1:0]!=2'b00 || ms_ade_exp[2] && ms_alu_result[0]!=1'b0) ?   `EXP_ADEL   :
                                    (ms_ade_exp[1] && ms_alu_result[1:0]!=2'b00 || ms_ade_exp[0] && ms_alu_result[0]!=1'b0) ?   `EXP_ADES   :
                                                                                                                                                5'h1f;

    wire            ms_ade_exp_unknown;
    assign          ms_ade_exp_unknown = (^ms_ade_exp === 1'bx);
    assign          ms_exp      =   ms_ade_exp_unknown ? es_to_ms_excode :
                                    &ms_excode         ? es_to_ms_excode : ms_excode;


    // 异常处理处理store指令，传到exe级，若ms级有异常而异常指令之后的指令就是
    // store指令，则store指令不能写数据存储器
    // assign          ms_to_es_excp   = ~(&es_to_ms_excode);
    // 仅当MEM级确有有效指令时，才向EXE级传递例外/eret阻塞信号;
    // 否则MEM空(void)时es_to_ms_bus_r为陈旧数据，会使ms_inst_eret/ms_exp
    // 维持有效，永久阻塞EXE的访存请求(死锁)。见第八章8.2.2节。
    assign          ms_to_es_excp   = ms_valid && ~(&ms_exp);
    assign          ms_to_es_eret   = ms_valid && ms_inst_eret;

    // 逐级互锁
    wire        ms_ready_go;
    wire        ms_need_data_ok;
    // 地址错例外时不应等待 data_ok；WB 级冲刷时亦应丢弃未完成的访存
    assign ms_need_data_ok   = (|ms_res_from_mem || |ms_ade_exp) & ~fs_to_ms_adel & (&ms_exp);
    assign ms_ready_go       = !ms_need_data_ok || data_sram_data_ok
                               || ws_to_ms_excp || ws_to_ms_eret;
    assign ms_allowin        = !ms_valid || (ms_ready_go && ws_allowin)
                               || ws_to_ms_excp || ws_to_ms_eret;
    assign ms_to_ws_valid    = ms_valid && ms_ready_go && ~ws_to_ms_excp && ~ws_to_ms_eret;
    assign ms_to_es_handoff  = ms_valid && ms_need_data_ok && data_sram_data_ok
                               && ms_allowin && es_to_ms_wants && es_incoming_mem;
    always @(posedge clk) begin
        if (reset) begin
            ms_valid <= 1'b0;
        end
        else if (ms_allowin) begin
            ms_valid <= es_to_ms_valid;
        end

        if (es_to_ms_valid && ms_allowin) begin
            es_to_ms_bus_r  <= es_to_ms_bus;
        end
    end

    // 传向后级数据
    reg [31:0] inst_lwr_data;
    reg [31:0] inst_lwl_data;
    reg [7:0]  inst_lb_data;
    reg [15:0] inst_lh_data;
    always@(*) begin
        case(ms_alu_result[1:0])
            2'b00 : begin   inst_lwl_data   = {data_sram_rdata[7:0], ms_rt_value[23:0]};     
                            inst_lwr_data   = data_sram_rdata;
                            inst_lb_data    = data_sram_rdata[7:0];
                            inst_lh_data    = data_sram_rdata[15:0];    end

            2'b01 : begin   inst_lwl_data   = {data_sram_rdata[15:0], ms_rt_value[15:0]};    
                            inst_lwr_data   = {ms_rt_value[31:24], data_sram_rdata[31:8]};     
                            inst_lb_data    = data_sram_rdata[15:8];
                            inst_lh_data    = 16'd0;                    end

            2'b10 : begin   inst_lwl_data   = {data_sram_rdata[23:0], ms_rt_value[7:0]};     
                            inst_lwr_data   = {ms_rt_value[31:16], data_sram_rdata[31:16]};
                            inst_lb_data    = data_sram_rdata[23:16];
                            inst_lh_data    = data_sram_rdata[31:16];   end

            2'b11 : begin   inst_lwl_data   = data_sram_rdata;
                            inst_lwr_data   = {ms_rt_value[31:8], data_sram_rdata[31:24]};
                            inst_lb_data    = data_sram_rdata[31:24];
                            inst_lh_data    = 16'd0;                    end

            default: begin  inst_lwl_data   = 32'd0;                      
                            inst_lwr_data   = 32'd0;
                            inst_lb_data    = 8'd0;
                            inst_lh_data    = 16'd0;                    end
        endcase
    end
    
    wire [31:0] mem_result;
    wire [31:0] ms_final_result;
    assign mem_result = ms_res_from_mem[0]  ?   data_sram_rdata                         :
                        ms_res_from_mem[1]  ?   {{24{inst_lb_data[7]}}, inst_lb_data}   :
                        ms_res_from_mem[2]  ?   {{24{1'b0}}, inst_lb_data}              :
                        ms_res_from_mem[3]  ?   {{16{inst_lh_data[15]}}, inst_lh_data}  :
                        ms_res_from_mem[4]  ?   {{16{1'b0}}, inst_lh_data}              :
                        ms_res_from_mem[5]  ?   inst_lwl_data                           :
                        ms_res_from_mem[6]  ?   inst_lwr_data                           :
                                                32'd0                                   ;
    assign ms_final_result = (ms_res_from_mem && (&ms_excode))  ?   mem_result  : 
                             ms_inst_mfhi                       ?   hi_to_rf    :
                             ms_inst_mflo                       ?   lo_to_rf    :  
                             ms_inst_mtc0                       ?   ms_rt_value :   ms_alu_result;
    assign ms_to_ws_bus = {ms_bd_slot     ,
                           fs_to_ms_adel  ,
                           fs_to_ms_epc   ,
                           ms_inst_eret   ,
                           ms_cp0_addr    ,
                           ms_intr        ,
                           ms_exp         ,
                           ms_inst_mfc0   ,
                           ms_inst_mtc0   ,
                           ms_sel         ,
                           ms_gr_we       ,  //69:69
                           ms_dest        ,  //68:64
                           ms_final_result,  //63:32
                           ms_pc             //31:0
                          };

    // bypass network
    wire        dest_zero;
    wire        forward_enable;
    wire        ms_load_op;
    assign ms_load_op = ms_res_from_mem;
    assign dest_zero = (ms_dest == 5'b0);
    assign forward_enable = ms_gr_we & ~dest_zero & ms_valid;
    // mfc0 的结果来自 CP0(cp0_rd_data)，仅在 WB 级写回寄存器堆后才有效；
    // MEM 级前递的是 ms_alu_result，并非 cp0_rd_data。故 mfc0 在 MEM 级时
    // 必须强制后级阻塞，直到其进入 WB 并完成写回，后继指令才能从寄存器堆
    // 读到正确值。load 则仅在数据未就绪(ms_ready_go=0)时阻塞。
    assign dep_need_stall = ms_valid & ~dest_zero
                            & (ms_inst_mfc0 || (ms_load_op && !ms_ready_go));
    //assign dep_need_stall = ms_inst_mfc0 || ms_load_op;
    assign ms_to_ds_forward_bus = { dep_need_stall,
                                    forward_enable,
                                    ms_dest,
                                    ms_final_result};
endmodule
