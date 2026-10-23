`include "mycpu.h"

// id_stage中为reg信号的是ds_valid 为1表示有一条有效指令在id
// fs_to_ds_bus_r 从if锁存的级间总线，拆出ds_pc, ds_inst, fs_to_ds_exp, fs_to_ds_epc等
// bd_slot 分支延迟槽标记，当前id指令是否在延迟槽内，遇inst_jbr置1，否则置0，进入ds_to_es_bus，供后面例外处理使用

module id_stage(
    input                          clk           ,
    input                          reset         ,
    //allowin
    input                          es_allowin    ,
    output                         ds_allowin    ,
    //from fs
    input                          fs_to_ds_valid,
    input  [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus  ,
    //to es
    output                         ds_to_es_valid,
    output [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus  ,
    //to fs
    output [`BR_BUS_WD       -1:0] br_bus        ,
    //to rf: for write back
    input  [`WS_TO_RF_BUS_WD -1:0] ws_to_rf_bus,


    input IF_over,

    input [`ES_TO_DS_FORWARD_BUS -1:0] es_to_ds_forward_bus,
    input [`MS_TO_DS_FORWARD_BUS -1:0] ms_to_ds_forward_bus,
    input [`WS_TO_DS_FORWARD_BUS -1:0] ws_to_ds_forward_bus,
    input                               ws_to_ds_excp,
    input                               ws_to_ds_eret
);

    reg         ds_valid   ;
    wire        ds_ready_go;

    wire [31                 :0] fs_pc;
    reg  [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus_r;
    assign fs_pc = fs_to_ds_bus[31:0];

    wire [ 4:0] fs_to_ds_exp;
    wire [31:0] ds_pc  ;
    wire [31:0] ds_inst;
    wire [31:0] fs_to_ds_epc;
    wire        fs_to_ds_adel;
    assign {fs_to_ds_adel   ,
            fs_to_ds_epc    ,
            fs_to_ds_exp    ,
            ds_inst         ,
            ds_pc  } = fs_to_ds_bus_r;

    // 写回级传到寄存器堆的数据
    wire        rf_we   ;
    wire [ 4:0] rf_waddr;
    wire [31:0] rf_wdata;
    assign {rf_we   ,  //37:37
            rf_waddr,  //36:32
            rf_wdata   //31:0
                    } = ws_to_rf_bus;

    wire        br_taken;
    wire [31:0] br_target;

    wire [15:0] alu_op;
    wire [6:0]  load_op;
    wire        src1_is_sa;
    wire        src1_is_pc;
    wire        src2_is_imm_s;
    wire        src2_is_imm_u;
    wire        src2_is_8;
    wire        res_from_mem;
    wire        gr_we;
    wire [4:0]  mem_we;
    wire [ 4:0] dest;
    wire [15:0] imm;
    wire [31:0] rs_value;
    wire [31:0] rt_value;
    wire [2 :0] sel;
    wire [5:0]  ds_intr;
    wire [4:0]  ds_exp;        
    wire        ds_ov_exp;                 // 有可能产生Int例外的指令
    wire [3:0]  ds_ade_exp;                 // 有可能产生AdE例外的指令
    wire [4:0]  ds_cp0_addr;
    reg         bd_slot;


    wire [ 5:0] op;
    wire [ 4:0] rs;
    wire [ 4:0] rt;
    wire [ 4:0] rd;
    wire [ 4:0] sa;
    wire [ 5:0] func;
    wire [25:0] jidx;
    wire [63:0] op_d;
    wire [31:0] rs_d;
    wire [31:0] rt_d;
    wire [31:0] rd_d;
    wire [31:0] sa_d;
    wire [63:0] func_d;

    // 区别是什么指令
    wire        inst_addu;
    wire        inst_subu;
    wire        inst_slt;
    wire        inst_sltu;
    wire        inst_and;
    wire        inst_or;
    wire        inst_xor;
    wire        inst_nor;
    wire        inst_sll;
    wire        inst_srl;
    wire        inst_sra;
    wire        inst_addiu;
    wire        inst_lui;
    wire        inst_lw;
    wire        inst_sw;
    wire        inst_beq;
    wire        inst_bne;
    wire        inst_jal;
    wire        inst_jr;

    wire        inst_add;
    wire        inst_addi;
    wire        inst_sub;
    wire        inst_slti;
    wire        inst_sltiu;
    wire        inst_andi;
    wire        inst_ori;
    wire        inst_xori;
    wire        inst_sllv;
    wire        inst_srav;
    wire        inst_srlv;
    wire        inst_mult;
    wire        inst_multu;
    wire        inst_div;
    wire        inst_divu;
    wire        inst_mfhi;
    wire        inst_mflo;
    wire        inst_mthi;
    wire        inst_mtlo;

    wire        inst_bgez;
    wire        inst_bgtz;
    wire        inst_blez;
    wire        inst_bltz;
    wire        inst_j;
    wire        inst_bltzal;
    wire        inst_bgezal;
    wire        inst_jalr;
    wire        inst_lb;
    wire        inst_lbu;
    wire        inst_lh;
    wire        inst_lhu;
    wire        inst_lwl;
    wire        inst_lwr;
    wire        inst_sb;
    wire        inst_sh;
    wire        inst_swl;
    wire        inst_swr;

    wire        inst_mtc0;
    wire        inst_mfc0;
    wire        inst_eret;
    wire        inst_syscall;
    wire        inst_break;

    // 目标寄存器是31号寄存器或者rt
    wire        dst_is_r31;  
    wire        dst_is_rt;   

    wire [ 4:0] rf_raddr1;
    wire [31:0] rf_rdata1;
    wire [ 4:0] rf_raddr2;
    wire [31:0] rf_rdata2;

    wire        rs_eq_rt;

    assign br_bus       = {br_taken,br_target};

    // clean control signals: override with 0 when IF-detected ADEL to avoid X contamination
    wire [15:0] cln_alu_op;
    wire [ 6:0] cln_load_op;
    wire        cln_src2_is_imm_u;
    wire        cln_src1_is_sa;
    wire        cln_src1_is_pc;
    wire        cln_src2_is_imm_s;
    wire        cln_src2_is_8;
    wire        cln_gr_we;
    wire [ 4:0] cln_mem_we;
    assign cln_alu_op       = fs_to_ds_adel ? 16'h0    : alu_op;
    assign cln_load_op      = fs_to_ds_adel ?  7'h0    : load_op;
    assign cln_src2_is_imm_u= fs_to_ds_adel ?  1'b0    : src2_is_imm_u;
    assign cln_src1_is_sa   = fs_to_ds_adel ?  1'b0    : src1_is_sa;
    assign cln_src1_is_pc   = fs_to_ds_adel ?  1'b0    : src1_is_pc;
    assign cln_src2_is_imm_s= fs_to_ds_adel ?  1'b0    : src2_is_imm_s;
    assign cln_src2_is_8    = fs_to_ds_adel ?  1'b0    : src2_is_8;
    assign cln_gr_we        = fs_to_ds_adel ?  1'b0    : gr_we;
    assign cln_mem_we       = fs_to_ds_adel ?  5'h0    : mem_we;

    // 传递到下一级的数据
    assign ds_to_es_bus = {bd_slot       ,
                           fs_to_ds_adel ,
                           fs_to_ds_epc  ,
                           inst_eret     ,
                           ds_cp0_addr   ,
                           ds_ade_exp    ,
                           ds_ov_exp     ,
                           ds_intr       ,
                           ds_exp        ,
                           inst_mfc0     ,
                           inst_mtc0     ,
                           sel           ,
                           inst_mfhi     ,  //144:144
                           inst_mflo     ,  //143:143
                           inst_mthi     ,  //142:142
                           inst_mtlo     ,  //141:141
                           cln_src2_is_imm_u,  //140:140
                           cln_alu_op    ,  //139:124
                           cln_load_op   ,  //123:129
                           cln_src1_is_sa,  //122:122
                           cln_src1_is_pc,  //121:121
                           cln_src2_is_imm_s,  //120:120
                           cln_src2_is_8 ,  // 1b   
                           cln_gr_we     ,  // 1b
                           cln_mem_we    ,  // 1b
                           fs_to_ds_adel ? 5'h0 : dest,  // 5b
                           imm           ,  // 32b
                           rs_value      ,  // 32b
                           rt_value      ,  // 32b
                           ds_pc            // 32b
                                    };


    assign ds_allowin     = !ds_valid || ds_ready_go && es_allowin;
    assign ds_to_es_valid =  ds_valid && ds_ready_go && ~ws_to_ds_excp && ~ws_to_ds_eret;
    always @(posedge clk) begin
        if (reset)
            ds_valid <= 1'b0;
        else if (ds_allowin) 
            ds_valid <= fs_to_ds_valid;

        if (fs_to_ds_valid && ds_allowin) begin
            fs_to_ds_bus_r <= fs_to_ds_bus;
        end
    end

    assign op   = ds_inst[31:26];
    assign rs   = ds_inst[25:21];
    assign rt   = ds_inst[20:16];
    assign rd   = ds_inst[15:11];
    assign sa   = ds_inst[10: 6];
    assign func = ds_inst[ 5: 0];
    assign imm  = ds_inst[15: 0];
    assign jidx = ds_inst[25: 0];
    assign sel  = ds_inst[2 : 0];

    decoder_6_64 u_dec0(.in(op  ), .out(op_d  ));
    decoder_6_64 u_dec1(.in(func), .out(func_d));
    decoder_5_32 u_dec2(.in(rs  ), .out(rs_d  ));
    decoder_5_32 u_dec3(.in(rt  ), .out(rt_d  ));
    decoder_5_32 u_dec4(.in(rd  ), .out(rd_d  ));
    decoder_5_32 u_dec5(.in(sa  ), .out(sa_d  ));
    
    // 共19条指令
    assign inst_addu   = op_d[6'h00] & func_d[6'h21] & sa_d[5'h00];
    assign inst_subu   = op_d[6'h00] & func_d[6'h23] & sa_d[5'h00];
    assign inst_slt    = op_d[6'h00] & func_d[6'h2a] & sa_d[5'h00];
    assign inst_sltu   = op_d[6'h00] & func_d[6'h2b] & sa_d[5'h00];
    assign inst_and    = op_d[6'h00] & func_d[6'h24] & sa_d[5'h00];
    assign inst_or     = op_d[6'h00] & func_d[6'h25] & sa_d[5'h00];
    assign inst_xor    = op_d[6'h00] & func_d[6'h26] & sa_d[5'h00];
    assign inst_nor    = op_d[6'h00] & func_d[6'h27] & sa_d[5'h00];
    assign inst_sll    = op_d[6'h00] & func_d[6'h00] & rs_d[5'h00];
    assign inst_srl    = op_d[6'h00] & func_d[6'h02] & rs_d[5'h00];
    assign inst_sra    = op_d[6'h00] & func_d[6'h03] & rs_d[5'h00];
    assign inst_addiu  = op_d[6'h09];
    assign inst_lui    = op_d[6'h0f] & rs_d[5'h00];
    assign inst_lw     = op_d[6'h23];
    assign inst_sw     = op_d[6'h2b];
    assign inst_beq    = op_d[6'h04];
    assign inst_bne    = op_d[6'h05];
    assign inst_jal    = op_d[6'h03];
    assign inst_jr     = op_d[6'h00] & func_d[6'h08] & rt_d[5'h00] & rd_d[5'h00] & sa_d[5'h00];

    assign inst_add    = op_d[6'h00] & func_d[6'h20] & sa_d[5'h00];
    assign inst_addi   = op_d[6'h08];
    assign inst_sub    = op_d[6'h00] & func_d[6'h22];
    assign inst_slti   = op_d[6'h0a];
    assign inst_sltiu  = op_d[6'h0b];
    assign inst_andi   = op_d[6'h0c];
    assign inst_ori    = op_d[6'h0d];
    assign inst_xori   = op_d[6'h0e];
    assign inst_sllv   = op_d[6'h00] & func_d[6'h04];
    assign inst_srav   = op_d[6'h00] & func_d[6'h07];
    assign inst_srlv   = op_d[6'h00] & func_d[6'h06];
    assign inst_mult   = op_d[6'h00] & func_d[6'h18];
    assign inst_multu  = op_d[6'h00] & func_d[6'h19];
    assign inst_div    = op_d[6'h00] & func_d[6'h1a];
    assign inst_divu   = op_d[6'h00] & func_d[6'h1b];
    assign inst_mfhi   = op_d[6'h00] & func_d[6'h10];
    assign inst_mflo   = op_d[6'h00] & func_d[6'h12];
    assign inst_mthi   = op_d[6'h00] & func_d[6'h11];
    assign inst_mtlo   = op_d[6'h00] & func_d[6'h13];

    assign inst_bgez   = op_d[6'h01] & rt_d[5'h01];
    assign inst_bgtz   = op_d[6'h07] & rt_d[5'h00];
    assign inst_blez   = op_d[6'h06] & rt_d[5'h00];
    assign inst_bltz   = op_d[6'h01] & rt_d[5'h00];
    assign inst_bgezal = op_d[6'h01] & rt_d[5'h11];
    assign inst_bltzal = op_d[6'h01] & rt_d[5'h10];
    assign inst_j      = op_d[6'h02];
    assign inst_jalr   = op_d[6'h00] & func_d[6'h09] & sa_d[5'h00] & rt_d[5'h00];
    assign inst_lb     = op_d[6'h20];
    assign inst_lbu    = op_d[6'h24];
    assign inst_lh     = op_d[6'h21];
    assign inst_lhu    = op_d[6'h25];
    assign inst_lwl    = op_d[6'h22];
    assign inst_lwr    = op_d[6'h26];
    assign inst_sb     = op_d[6'h28];
    assign inst_sh     = op_d[6'h29];
    assign inst_swl    = op_d[6'h2a];
    assign inst_swr    = op_d[6'h2e];

    assign inst_syscall = op_d[6'h00] & func_d[6'h0c];
    assign inst_break   = op_d[6'h00] & func_d[6'h0d];
    assign inst_eret    = op_d[6'h10] & func_d[6'h18];
    assign inst_mfc0    = op_d[6'h10] & rs_d[5'h00];
    assign inst_mtc0    = op_d[6'h10] & rs_d[5'h04];

    // 有些指令不需要经过alu，包括：jr, bne, beq,
    // jr是无条件跳转直接跳转到rs中的值，而beq, bne跳转地址的产生需要加法，但
    // 但是是在后面的br_target信号中加的
    assign alu_op[ 0] = inst_addu | inst_addiu | inst_lw | inst_sw | inst_jal | inst_add | inst_addi | inst_bgezal | inst_bltzal | inst_jalr |
                        inst_lb | inst_lbu | inst_lh | inst_lhu | inst_lwl | inst_lwr | inst_sb | inst_sh | inst_swl | inst_swr;
    assign alu_op[ 1] = inst_subu | inst_sub;
    assign alu_op[ 2] = inst_slt  | inst_slti;
    assign alu_op[ 3] = inst_sltu | inst_sltiu;
    assign alu_op[ 4] = inst_and  | inst_andi;
    assign alu_op[ 5] = inst_nor;
    assign alu_op[ 6] = inst_or   | inst_ori;
    assign alu_op[ 7] = inst_xor  | inst_xori;
    assign alu_op[ 8] = inst_sll  | inst_sllv;
    assign alu_op[ 9] = inst_srl  | inst_srlv;
    assign alu_op[10] = inst_sra  | inst_srav;
    assign alu_op[11] = inst_lui;
    assign alu_op[12] = inst_div;
    assign alu_op[13] = inst_divu;
    assign alu_op[14] = inst_mult;
    assign alu_op[15] = inst_multu;


    // 对load指令特殊处理
    assign load_op[0]       = inst_lw; 
    assign load_op[1]       = inst_lb;
    assign load_op[2]       = inst_lbu;
    assign load_op[3]       = inst_lh;
    assign load_op[4]       = inst_lhu;
    assign load_op[5]       = inst_lwl;
    assign load_op[6]       = inst_lwr;

    assign src1_is_sa       = inst_sll | inst_srl | inst_sra;
    assign src1_is_pc       = inst_jal | inst_bgezal | inst_bltzal | inst_jalr;
    assign src2_is_imm_s    = inst_addiu | inst_lui | inst_lw | inst_sw | inst_slti | inst_sltiu | inst_addi | 
                                inst_lb | inst_lbu | inst_lh | inst_lhu | inst_lwl | inst_lwr | inst_sb | inst_sh | inst_swl | inst_swr;
    assign src2_is_imm_u    = inst_andi | inst_ori | inst_xori;
    assign src2_is_8        = inst_jal | inst_bgezal | inst_bltzal | inst_jalr;
    assign res_from_mem     = inst_lw | inst_lb | inst_lbu | inst_lh | inst_lhu | inst_lwl | inst_lwr;
    assign dst_is_r31       = inst_jal | inst_bgezal | inst_bltzal;
    assign dst_is_rt        = inst_addiu | inst_lui | inst_lw | inst_slti | inst_sltiu | inst_andi | inst_ori | inst_xori | inst_addi | 
                                inst_lb | inst_lbu | inst_lh | inst_lhu | inst_lwl | inst_lwr | inst_mfc0;
    assign gr_we            = ~inst_sw & ~inst_beq & ~inst_bne & ~inst_jr & ~inst_j & ~inst_bgez & ~inst_bgtz & ~inst_blez & ~inst_bltz &
                                ~inst_sb & ~inst_sh & ~inst_swl & ~inst_swr & ~inst_mtc0;
    assign mem_we[0]        = inst_sw;
    assign mem_we[1]        = inst_sb;
    assign mem_we[2]        = inst_sh;
    assign mem_we[3]        = inst_swl;
    assign mem_we[4]        = inst_swr;

    assign dest         = dst_is_r31 ? 5'd31 :
                          dst_is_rt  ? rt    : 
                                       rd;

    // exception
    wire            resv_inst;
    wire    [4 :0]  id_excode;
    wire            ld_ade;
    wire            lh_lhu_ade;
    wire            sw_ade;
    wire            sh_ade;
    assign          ds_intr     = 6'h00;        // 中断无法测试，暂时全为0，也就是没有中断
    assign          resv_inst   =   ~inst_add & ~inst_addi & ~inst_addu & ~inst_addiu & ~inst_sub & ~inst_subu & ~inst_slt              &
                                    ~inst_slti & ~inst_sltu & ~inst_sltiu & ~inst_div & ~inst_divu & ~inst_mult & ~inst_multu           &
                                    ~inst_and & ~inst_andi & ~inst_lui & ~inst_nor & ~inst_or & ~inst_ori & ~inst_xor & ~inst_xori      &
                                    ~inst_sllv & ~inst_sll & ~inst_srav & ~inst_sra & ~inst_srlv & ~inst_srl & ~inst_beq & ~inst_bne    &
                                    ~inst_bgez & ~inst_bgtz & ~inst_blez & ~inst_bltz & ~inst_bgezal & ~inst_bltzal & ~inst_j           &
                                    ~inst_jal & ~inst_jr & ~inst_jalr & ~inst_mfhi & ~inst_mflo & ~inst_mthi & ~inst_mtlo & ~inst_break &
                                    ~inst_syscall & ~inst_lb & ~inst_lbu & ~inst_lh & ~inst_lhu & ~inst_lw & ~inst_lwl & ~inst_lwr      &
                                    ~inst_sb & ~inst_sh & ~inst_sw & ~inst_swl & ~inst_swr & ~inst_eret & ~inst_mfc0 & ~inst_mtc0       ;
    assign id_excode            =   inst_syscall    ?   `EXP_SYS    : 
                                    inst_break      ?   `EXP_BP     :
                                    resv_inst       ?   `EXP_RI     :
                                                        5'h1f       ;

    assign ds_exp               =   fs_to_ds_adel   ?   `EXP_ADEL       :
                                    &id_excode      ?   fs_to_ds_exp    :   id_excode;

    assign ds_ov_exp            = inst_add || inst_addi || inst_sub;
    
    assign  ld_ade              = inst_lw;
    assign  lh_lhu_ade          = inst_lh || inst_lhu;
    assign  sw_ade              = inst_sw;
    assign  sh_ade              = inst_sh;
    assign  ds_ade_exp          = {ld_ade, lh_lhu_ade, sw_ade, sh_ade};
    assign  ds_cp0_addr         = rd;


    // forward 处理

    wire        ms_forward_enable;   //前递使能信号
    wire [ 4:0] ms_forward_reg;      //前递的数据的的地址
    wire [31:0] ms_forward_data;     //前递的数据的值
    wire        ms_dep_need_stall;   //判断是否需要阻塞

    wire        es_dep_need_stall;
    wire        es_forward_enable;
    wire [ 4:0] es_forward_reg;
    wire [31:0] es_forward_data;

    wire        ws_dep_need_stall;
    wire        ws_forward_enable;
    wire [ 4:0] ws_forward_reg;
    wire [31:0] ws_forward_data;

    wire        rf1_forward_stall;  //阻塞信号
    wire        rf2_forward_stall;
    wire        inst_need_rs;   //是否需要读rs
    wire        inst_need_rt;   //是否需要读rt

	assign {es_dep_need_stall,      //控制es级是否阻塞
            es_forward_enable, 
            es_forward_reg   ,
            es_forward_data
            } = es_to_ds_forward_bus;

	assign {ms_dep_need_stall,      //控制ms级是否阻塞
            ms_forward_enable, 
            ms_forward_reg   ,
            ms_forward_data
            } = ms_to_ds_forward_bus;

	assign {ws_dep_need_stall,      // 控制ws级是否阻塞
            ws_forward_enable,
            ws_forward_reg   ,
            ws_forward_data
            } = ws_to_ds_forward_bus;

    //inst_need_rs用于判断是否需要读rs
    assign inst_need_rs = inst_addu    |   //rd,rs,rt
                          inst_addiu   |   //rt,rs,imm
                          inst_subu    |   //rd,rs,rt
                          inst_slt     |   //rd,rs,rt
                          inst_sltu    |   //rd,rs,rt                      
                          inst_and     |   //rd,rs,rt
                          inst_or      |   //rd,rs,rt
                          inst_xor     |   //rd,rs,rt
                          inst_nor     |   //rd,rs,rt
                          inst_lw      |   //rt,rs+offset
                          inst_sw      |   //rt,offset    
                          inst_beq     |   //rs,rt,offset 
                          inst_bne     |   //rs,rt,offset 
                          inst_jr      |   //rs

                          inst_add     |   //rd,rs,rt
                          inst_addi    |   //rt,rs,imm
                          inst_sub     |   //rd,rs,rt
                          inst_slt     |   //rt,rs,imm
                          inst_sltiu   |   //rt,rs,imm
                          inst_andi    |   //rt,rs,imm
                          inst_ori     |   //rt,rs,imm
                          inst_xori    |   //rt,rs,imm
                          inst_sllv    |   //rd,rs,rt
                          inst_srav    |   //rd,rs,rt
                          inst_srlv    |   //rd,rs,rt
                          inst_div     |
                          inst_divu    |
                          inst_mult    |
                          inst_multu   |
                          inst_mthi    |
                          inst_mtlo    |

                          inst_bgez    |
                          inst_bgtz    |
                          inst_blez    |
                          inst_bltz    |
                          inst_bgezal  |
                          inst_bltzal  |
                          inst_jalr    |
                          inst_lb      |
                          inst_lbu     |
                          inst_lh      |
                          inst_lhu     |
                          inst_lwl     |
                          inst_lwr     |
                          inst_sb      |
                          inst_sh      |
                          inst_swl     |
                          inst_swr
                          ;
                      
    //inst_need_rt用于判断是否需要读rt
    assign inst_need_rt = inst_addu    |   //rd,rs,rt
                         // inst_addiu   |   //rt,rs,imm
                          inst_subu    |   //rd,rs,rt
                          inst_slt     |   //rd,rs,rt
                          inst_sltu    |   //rd,rs,rt                      
                          inst_and     |   //rd,rs,rt
                          inst_or      |   //rd,rs,rt
                          inst_xor     |   //rd,rs,rt
                          inst_nor     |   //rd,rs,rt
                          inst_lui     |   //rt,imm
                          inst_sll     |   //rd,rt,sa
                          inst_sra     |   //rd,rt,sa
                          inst_srl     |   //rd,rt,sa
                          inst_lw      |   //rt,offset
                          inst_sw      |   //rt,offset 
                          inst_beq     |   //rs,rt,offset 
                          inst_bne     |   //rs,rt,offset 

                          inst_add     |   //rd,rs,rt
                          // inst_addi    |   //rt,rs,imm
                          inst_sub     |   //rd,rs,rt
                          inst_slti    |   //rt,rs,imm
                          inst_sltiu   |   //rt,rs,imm
                          inst_andi    |   //rt,rs,imm
                          inst_ori     |   //rt,rs,imm
                          inst_xori    |   //rt,rs,imm
                          inst_sllv    |   //rd,rt,rs
                          inst_srav    |   //rd,rt,rs
                          inst_srlv    |   //rd,rt,rs
                          inst_div     |
                          inst_divu    |
                          inst_mult    |
                          inst_multu   |
                          inst_sb      |
                          inst_sh      |
                          inst_swl     |
                          inst_swr     |
                          inst_lwl     |
                          inst_lwr     |
                          inst_mtc0
                          ;


    wire        inst_jbr;   //所有分支跳转指令
    assign      inst_jbr = inst_jal | inst_beq | inst_bne | inst_jr | inst_j | inst_bgez | inst_bgtz | inst_blez | inst_bltz | inst_bgezal 
                            | inst_bltzal | inst_jalr;
    always@(posedge clk) begin
        if (reset)
            bd_slot <= 1'b0;
        else if (inst_jbr)
            bd_slot <= 1'b1;
        else
            bd_slot <= 1'b0;
    end
    
    //exe stage first forward    选择器选择前递的数据且有优先顺序EXE>MEM>WB
    //inst_need_rs也可以不用判断，因为rf_raddr1 == es_forward_reg如果相同且es_forward_enable为1那么就一定要把前递过来的数据赋给rs_value
    assign {rf1_forward_stall, rs_value} =  ((rf_raddr1 == es_forward_reg) && es_forward_enable && inst_need_rs) ? {es_dep_need_stall, es_forward_data} :   
                                            ((rf_raddr1 == ms_forward_reg) && ms_forward_enable && inst_need_rs) ? {ms_dep_need_stall, ms_forward_data} :
                                            ((rf_raddr1 == ws_forward_reg) && ws_forward_enable && inst_need_rs) ? {ws_dep_need_stall,ws_forward_data} :  
                                            {1'b0, rf_rdata1}; 
    //inst_need_rt同理上面inst_need_rs
    assign {rf2_forward_stall, rt_value} = ((rf_raddr2 == es_forward_reg) && es_forward_enable && inst_need_rt) ? {es_dep_need_stall, es_forward_data} :
                                           ((rf_raddr2 == ms_forward_reg) && ms_forward_enable && inst_need_rt) ? {ms_dep_need_stall, ms_forward_data} :
                                           ((rf_raddr2 == ws_forward_reg) && ws_forward_enable && inst_need_rt) ? {ws_dep_need_stall,ws_forward_data} :
 			    						   {1'b0, rf_rdata2};

    //ds_ready_go信号要做出相应的调整
    assign ds_ready_go    = ds_valid & (fs_to_ds_adel || (~rf1_forward_stall & ~rf2_forward_stall & (~inst_jbr | IF_over))) || ws_to_ds_eret || ws_to_ds_excp;

    // 寄存器堆的读是当拍给地址，则当拍给数据
    // 同步RAM的读是当拍给地址，下一拍给数据，这一点具体可看if的代码
    assign rf_raddr1 = rs;
    assign rf_raddr2 = rt;
    regfile u_regfile(
        .clk    (clk      ),
        .raddr1 (rf_raddr1),
        .rdata1 (rf_rdata1),
        .raddr2 (rf_raddr2),
        .rdata2 (rf_rdata2),
        .we     (rf_we    ),
        .waddr  (rf_waddr ),
        .wdata  (rf_wdata )
        );

    assign rs_eq_rt = (rs_value == rt_value);
    // br_taken 必须在操作数稳定(无前递阻塞)且本拍确实要提交时才可置起,
    // 否则会在操作数尚未就绪的首拍用错误的转发值(例如load地址)做出跳转判决,
    // 并被IF级锁存, 导致误跳转。
    assign br_taken = (   inst_beq  &&  rs_eq_rt
                       || inst_bne  && !rs_eq_rt
                       || inst_jal
                       || inst_jr
                       || inst_j
                       || inst_bgez && (rs_value[31]==1'b0)
                       || inst_bgtz && (rs_value[31]==1'b0 && |rs_value!=0) 
                       || inst_blez && (rs_value[31]==1'b1 || |rs_value==0)
                       || inst_bltz && (rs_value[31]==1'b1)
                       || inst_bgezal && (rs_value[31]==1'b0)
                       || inst_bltzal && (rs_value[31]==1'b1)
                       || inst_jalr
                      ) && ds_valid && ds_ready_go;
    // MIPS跳转地址相对的是 (分支inst对应的延迟槽pc)+4，而此时ds_pc是分支pc，而fs_pc正好是延迟槽pc
    // 故在锁存fs_to_ds_bus之前就将fs_pc取出，在这里使用
    // 注意: 不能使用 fs_pc 作为基址, 因为引入类SRAM接口后 IF 级(fs)可能落后于 DS 级,
    // fs_pc 不一定恰好是延迟槽的PC。延迟槽PC恒等于 ds_pc+4, 用它作为基址才是稳健的。
    wire [31:0] br_base_pc = ds_pc + 32'd4;
    assign br_target = (inst_beq || inst_bne || inst_bgez || inst_bgtz || 
                        inst_blez || inst_bltz || inst_bgezal || inst_bltzal)   ? (br_base_pc + {{14{imm[15]}}, imm[15:0], 2'b0})    :
                       (inst_jr  || inst_jalr)                                  ? rs_value                                      :
                                                {br_base_pc[31:28], jidx[25:0], 2'b0};

    // DEBUG
    // always @(posedge clk) begin
    //     if (!reset && ds_valid)
    //         $display("DS pc=%h inst=%h rsval=%h rtval=%h fspc=%h brtgt=%h brtkn=%b", ds_pc, ds_inst, rs_value, rt_value, fs_pc, br_target, br_taken);
    // end

endmodule
