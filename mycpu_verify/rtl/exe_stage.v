`include "mycpu.h"

module exe_stage(
    input                           clk             ,
    input                           reset           ,
    //allowin
    input                           ms_allowin      ,
    output                          es_allowin      ,
    //from ds
    input                           ds_to_es_valid  ,
    input  [`DS_TO_ES_BUS_WD -1:0]  ds_to_es_bus    ,
    input                           ws_to_es_excp   ,
    input                           ws_to_es_eret   ,
    input                           ms_to_es_excp   ,
    input                           ms_to_es_eret   ,
    input                           ms_to_es_handoff,
    //to ms
    output                          es_to_ms_valid  ,
    output                          es_to_ms_wants  ,
    output                          es_incoming_mem  ,
    output [`ES_TO_MS_BUS_WD -1:0]  es_to_ms_bus    ,


    // data sram interface
    output                          data_sram_req   ,
    output                          data_sram_wr    ,
    output [ 1:0]                   data_sram_size  ,
    output [ 3:0]                   data_sram_wstrb ,
    output [31:0]                   data_sram_addr  ,
    output [31:0]                   data_sram_wdata ,
    input                           data_sram_addr_ok ,

    //output [4:0]  EXE_wdest
    output [`ES_TO_DS_FORWARD_BUS -1:0] es_to_ds_forward_bus
);

    // 接受前级传递的信号
    reg  [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus_r;
    wire [5:0]  es_intr             ;
    wire [4:0]  ds_to_es_excode     ;
    wire        es_inst_mfc0        ;
    wire        es_inst_mtc0        ;
    wire [2:0]  es_sel              ;
    wire        es_inst_mfhi        ;
    wire        es_inst_mflo        ;
    wire        es_inst_mthi        ;
    wire        es_inst_mtlo        ;
    wire        es_src2_is_imm_u    ;
    wire [15:0] es_alu_op           ;
    wire [6:0]  es_load_op          ;
    wire        es_src1_is_sa       ;  
    wire        es_src1_is_pc       ;
    wire        es_src2_is_imm_s    ; 
    wire        es_src2_is_8        ;
    wire        es_gr_we            ;
    wire [ 4:0] es_mem_we           ;
    wire [ 4:0] es_dest             ;
    wire [15:0] es_imm              ;
    wire [31:0] es_rs_value         ;
    wire [31:0] es_rt_value         ;
    wire [31:0] es_pc               ;
    wire        es_ov_exp           ;
    wire [3:0]  es_ade_exp          ;
    wire [4:0]  es_cp0_addr         ;
    wire        es_inst_eret        ;
    wire [31:0] fs_to_es_epc        ;
    wire        fs_to_es_adel       ;
    wire        es_bd_slot          ;
    assign {es_bd_slot          ,
            fs_to_es_adel       ,
            fs_to_es_epc        ,
            es_inst_eret        ,
            es_cp0_addr         ,
            es_ade_exp          ,
            es_ov_exp           ,
            es_intr             ,
            ds_to_es_excode     ,
            es_inst_mfc0        ,
            es_inst_mtc0        ,
            es_sel              ,
            es_inst_mfhi        ,
            es_inst_mflo        ,
            es_inst_mthi        ,
            es_inst_mtlo        ,
            es_src2_is_imm_u    , //140:140
            es_alu_op           ,  //139:124
            es_load_op          ,  //123:123
            es_src1_is_sa       ,  //122:122
            es_src1_is_pc       ,  //121:121
            es_src2_is_imm_s    ,  //120:120
            es_src2_is_8        ,  //119:119
            es_gr_we            ,  //118:118
            es_mem_we           ,  //117:117
            es_dest             ,  //116:112
            es_imm              ,  //111:96
            es_rs_value         ,  //95 :64
            es_rt_value         ,  //63 :32
            es_pc                  //31 :0
           } = ds_to_es_bus_r;



    wire        div;
    wire        mul;
    wire        es_mem_op;
    wire        data_addr_ok;
    wire        es_start_mem;
    wire        es_no_mem_wb;
    reg         es_dreq;
    // 流水线逐级互锁
    reg         es_valid      ;
    wire        es_ready_go   ;
    assign es_mem_op     = (|es_mem_we || |es_load_op) && !fs_to_es_adel;
    assign data_addr_ok  = es_dreq && data_sram_addr_ok;
    assign es_no_mem_wb  = ws_to_es_excp || ws_to_es_eret || ms_to_es_excp || ms_to_es_eret;
    assign es_start_mem  = es_valid && es_mem_op && !div && !mul && !es_dreq && !es_no_mem_wb;
    assign es_ready_go   = !div && !mul && (!es_mem_op || data_addr_ok);
    // 当eret/例外到达WB级(ws_to_es_eret/excp)需冲刷后端流水时，EXE级中
    // 被阻塞的指令(访存或div/mult)必须被丢弃而不是一直握住，否则一旦
    // eret/例外离开WB、且ms_to_es_*已按ms_valid屏蔽(见mem_stage)，该指令
    // 会被错误地重新发起并更新访存/HI/LO。此处强制es_allowin=1以便EXE吞入
    // 气泡完成冲刷。
    assign es_allowin     = !es_valid || (es_ready_go && ms_allowin && !ms_to_es_handoff)
                            || ws_to_es_excp || ws_to_es_eret;
    assign es_incoming_mem = es_mem_op;
    assign es_to_ms_wants = es_valid && es_ready_go && (~es_mem_op || data_addr_ok)
                            && ~ws_to_es_excp && ~ws_to_es_eret;
    assign es_to_ms_valid = es_to_ms_wants && ~ms_to_es_handoff;
    always @(posedge clk) begin
        if (reset) begin
            es_valid <= 1'b0;
        end
        else if (es_allowin) begin
            es_valid <= ds_to_es_valid;
        end

        if (ds_to_es_valid && es_allowin) begin
            ds_to_es_bus_r <= ds_to_es_bus;
        end
    end

    wire [31:0] es_alu_src1     ;
    wire [31:0] es_alu_src2     ;
    wire [31:0] es_alu_result   ;
    wire        es_alu_ov       ;
    assign es_alu_src1 = es_src1_is_sa  ? {27'b0, es_imm[10:6]} : 
                         es_src1_is_pc  ? es_pc[31:0] :
                                          es_rs_value;
    assign es_alu_src2 = es_src2_is_imm_s ? {{16{es_imm[15]}}, es_imm[15:0]} : 
                         es_src2_is_imm_u ? {{16'h0}, es_imm[15:0]}          :
                         es_src2_is_8   ? 32'd8 :
                                          es_rt_value;

    alu u_alu(
        .alu_op     (es_alu_op[11:0]    ),
        .alu_src1   (es_alu_src1        ),
        .alu_src2   (es_alu_src2        ),
        .alu_result (es_alu_result      ),
        .alu_ov     (es_alu_ov         )
        );
   // exception 处理
   wire [4:0]   es_excode;
   wire [4:0]   es_exp  ;
   wire         back_end_need_stall;
   assign       es_excode   =   (es_ov_exp && es_alu_ov) ? `EXP_OV : 5'h1f;
   assign       es_exp      =   &es_excode ? ds_to_es_excode : es_excode    ;
   assign       back_end_need_stall = ms_to_es_excp || ms_to_es_eret || ws_to_es_excp || ws_to_es_eret;

    // divider
    wire    [31:0]  div_r;
    wire    [31:0]  div_s;
    wire            div_complete;
    reg     [5:0]   div_count;
    always@(posedge clk) begin
        if (es_alu_op[13:12] == 2'b00)
            div_count   <= 6'd0;
        else if (div_count==6'd32)
            div_count   <= 6'd0;
        else 
            div_count   <= div_count + 1'b1;
    end
    assign div      = ~fs_to_es_adel && (es_alu_op[12] ^ es_alu_op[13]) && (div_count!=6'd32) && (~back_end_need_stall);   
    div u_div(
        .div_clk    (clk                ),
        .reset      (reset              ),
        .div        (div                ),
        .div_signed (es_alu_op[12]      ),
        .x          (es_alu_src1        ),
        .y          (es_alu_src2        ),
        .s          (div_s               ),
        .r          (div_r               ),
        .complete   (div_complete        )
    );

    // multipler
    wire    [31:0]  mul_result_h;
    wire    [31:0]  mul_result_l;
    wire            mul_complete;
    reg     [1:0]   mul_count;
    always@(posedge clk) begin
        if (es_alu_op[15:14]==2'b00)
            mul_count   <= 2'b00;
        else if (mul_count==2'd2)
            mul_count   <= 2'b00;
        else
            mul_count   <= mul_count + 1'b1;
    end
    assign  mul     = ~fs_to_es_adel && (es_alu_op[15] ^ es_alu_op[14]) && (mul_count != 2'd2) && (~back_end_need_stall);
    mult_top u_mult_top (
        .mul_clk    (clk                ),
        .reset      (reset              ),
        .mul        (mul                ),
        .mul_signed (es_alu_op[14]      ),
        .x          (es_alu_src1        ),
        .y          (es_alu_src2        ),
        .result_h   (mul_result_h       ),
        .result_l   (mul_result_l       ),
        .complete   (mul_complete       )
        
    );


    wire    [31:0]  es_lo;
    wire    [31:0]  es_hi;
    assign es_lo    = (|es_alu_op[15:12] && div_complete) ? div_s : 
                      (|es_alu_op[15:12] && mul_complete) ? mul_result_l :
                                                            32'd0;
    assign es_hi    = (|es_alu_op[15:12] && div_complete) ? div_r : 
                      (|es_alu_op[15:12] && mul_complete) ? mul_result_h :
                                                            32'd0;

    // 传向后级的数据
    wire    [6:0]   es_res_from_mem;
    assign es_res_from_mem = es_load_op;     // load指令结果不在exe级，在mem级
    assign es_to_ms_bus = {es_bd_slot       ,
                           fs_to_es_adel    ,
                           fs_to_es_epc     ,
                           es_inst_eret     ,
                           es_cp0_addr      ,
                           es_ade_exp       ,
                           es_intr          ,
                           es_exp           ,
                           es_inst_mfc0     ,
                           es_inst_mtc0     ,
                           es_sel           ,
                           es_rt_value      ,
                           es_alu_op[15:12] , //171:174
                           es_inst_mfhi     ,  //170:170
                           es_inst_mflo     ,  //169:169
                           es_inst_mthi     ,  //168:168
                           es_inst_mtlo     ,  //167:167
                           es_alu_src1      ,  //135:166  
                           es_lo            ,  //103:134
                           es_hi            ,  //71:102
                           es_res_from_mem  ,  //70:70
                           es_gr_we         ,  //69:69
                           es_dest          ,  //68:64
                           es_alu_result    ,  //63:32
                           es_pc             //31:0
                          };
    
    // bypass network
    assign dest_zero = (es_dest == 5'b0);
    assign forward_enable = es_gr_we & ~dest_zero & es_valid;
    assign dep_need_stall = es_valid && (|es_load_op || es_inst_mfhi || es_inst_mflo || es_inst_mfc0);
    assign es_to_ds_forward_bus = { 
                                    dep_need_stall, 
                                    forward_enable,
                                    es_dest, 
                                    es_alu_result};
    
    

    reg [3:0]  sram_wen;
    reg [31:0] sram_wdata;
    always@(*) begin
        sram_wen   = 4'h0;
        sram_wdata = 32'h0;
        if(es_valid)
            case(es_alu_result[1:0])
                2'b00 : begin 
                    sram_wen    =   es_mem_we[0]    ?   4'hf    : 
                                    es_mem_we[1]    ?   4'h1    :
                                    es_mem_we[2]    ?   4'h3    :
                                    es_mem_we[3]    ?   4'h1    :
                                    es_mem_we[4]    ?   4'hf    :
                                                        4'h0    ;
                    sram_wdata  =   es_mem_we[3]    ?   {{24{1'b0}}, es_rt_value[31:24]}    : es_rt_value;
                end

                2'b01 : begin
                    sram_wen    =   es_mem_we[0]    ?   4'h0    :
                                    es_mem_we[1]    ?   4'h2    :
                                    es_mem_we[2]    ?   4'h0    :
                                    es_mem_we[3]    ?   4'h3    :
                                    es_mem_we[4]    ?   4'he    :
                                                        4'h0    ;
                    sram_wdata  =   es_mem_we[3]    ?   {{16{1'b0}}, es_rt_value[31:16]}    :   
                                    es_mem_we[4]    ?   {es_rt_value[23:0], {8{1'b0}}}      :
                                    es_mem_we[1]    ?   {{16'd0}, es_rt_value[7:0], {8'd0}} :
                                                        es_rt_value                         ;
                end

                2'b10 : begin
                    sram_wen    =   es_mem_we[0]    ?   4'h0    :
                                    es_mem_we[1]    ?   4'h4    :
                                    es_mem_we[2]    ?   4'hc    :
                                    es_mem_we[3]    ?   4'h7    :
                                    es_mem_we[4]    ?   4'hc    :
                                                        4'h0    ;
                    sram_wdata  =   es_mem_we[3]    ?   {{8{1'b0}}, es_rt_value[31:8]}      :
                                    es_mem_we[4]    ?   {es_rt_value[15:0], {16'd0}}        :
                                    es_mem_we[2]    ?   {es_rt_value[15:0], {16'd0}}        :
                                    es_mem_we[1]    ?   {{8'd0}, es_rt_value[7:0], {16'd0}} :
                                                        es_rt_value                         ;
                end

                2'b11 : begin
                    sram_wen    =   es_mem_we[0]    ?   4'h0    :
                                    es_mem_we[1]    ?   4'h8    :
                                    es_mem_we[2]    ?   4'h0    :
                                    es_mem_we[3]    ?   4'hf    :
                                    es_mem_we[4]    ?   4'h8    :
                                                        4'h0    ;
                    sram_wdata  =   es_mem_we[4]    ?   {es_rt_value[7:0], {24'd0}}         :   
                                    es_mem_we[1]    ?   {es_rt_value[7:0], {24'd0}}         :
                                                        es_rt_value;
                end
                default : sram_wen = 4'h0;
            endcase
        end


    always @(posedge clk) begin
        if (reset || es_no_mem_wb)
            es_dreq <= 1'b0;
        else if (data_addr_ok)
            es_dreq <= 1'b0;
        else if (es_start_mem)
            es_dreq <= 1'b1;
    end

    assign data_sram_req    = es_dreq;
    assign data_sram_wr     = |data_sram_wstrb;
    assign data_sram_size   = 2'b10;
    assign data_sram_addr   = es_alu_result;
    assign data_sram_wstrb  = es_no_mem_wb ? 4'h0 : sram_wen;
    assign data_sram_wdata  = sram_wdata;

endmodule
