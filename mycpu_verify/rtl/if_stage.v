`include "mycpu.h"

module if_stage(
    input                           clk             ,
    input                           reset           ,

    input                           ds_allowin      ,
    input  [`BR_BUS_WD       -1:0]  br_bus          ,

    input                           ws_to_fs_excp   ,
    input                           ws_to_fs_eret   ,
    input   [31:0]                  ws_to_fs_pc     ,

    output                          fs_to_ds_valid  ,
    output [`FS_TO_DS_BUS_WD -1:0]  fs_to_ds_bus    ,

    output                          inst_sram_req   ,
    output                          inst_sram_wr    ,
    output [ 1:0]                   inst_sram_size  ,
    output [ 3:0]                   inst_sram_wstrb ,
    output [31:0]                   inst_sram_addr  ,
    output [31:0]                   inst_sram_wdata ,
    input                           inst_sram_addr_ok,
    input                           inst_sram_data_ok,
    input  [31:0]                   inst_sram_rdata ,

    output reg                      IF_over
);

    wire         br_taken_w;
    wire [31:0]  br_target_w;
    assign {br_taken_w, br_target_w} = br_bus;

    // pre-IF 要处理的事情
    // 1. 锁存跳转信息
    // 2. 顺序取延迟槽（seq_pc）
    // 3. 延迟槽进fs (bd_done=1）
    // 4. 再改pc去br_target
    // 5. 跳转目标进if后结束

    // 顺序pc
    reg  [31:0] seq_pc;  
    // pfs发出请求，addr_ok返回，但fs还没allowin               
    reg         pfs_addr_ok_r;          
    // pfs收到inst，fs还收不了，缓存在buff中，有效位
    reg         pfs_inst_buff_valid;    
    // pfs收到inst，fs还收不了，缓存在buff中
    reg  [31:0] pfs_inst_buff;          
    // pfs_pc_buff是和pfs_inst_buff配对的pc缓存，fs背压先缓存在pfs，把取指对应的pc一起存下来
    reg  [31:0] pfs_pc_buff;            

    // br_bus buffer (PDF 8.2.1-4)
    // 无论如何，br_taken和br_target只要是跳转都锁存
    reg         br_taken_r;             
    reg  [31:0] br_target_r;
     // 没有bd_done_r，pfs无法记住跳转已经决定，但延迟槽还没完这个中间状态
    reg         bd_done_r;             

    // IF
    reg         fs_valid;
    // fs已经有pc，但还没拿到inst，就会等待返回的rdata，
    // 本质是因为pfs向fs传的逻辑是只要addr_ok即可传，而不是data_ok
    reg         fs_wait_data;           
    reg  [31:0] fs_pc;
    reg  [31:0] fs_inst_r;

    wire        br_taken;
    wire [31:0] br_target;
    wire        bd_done;

    wire [31:0] pfs_pc;
    wire        pfs_addr_ok;
    wire        pfs_ready_go;
    wire        pfs_to_fs_valid;
    // pfs里面，指令数据已经准备好，可以送给fs，数据来源可能有1.pfs_inst_buff；2.pfs_inst_sram_data_ok
    wire        pfs_inst_ok;            
    wire [31:0] pfs_inst;


    wire [31:0] fs_inst;
    wire        fs_ready_go;
    wire        fs_allowin;
    // 返回的rdata可能给pfs，也可能给fs，所以要仲裁一下给谁，为1时给pfs，为0时给fs
    wire        fs_inst_unable;
    
    // sarm的data_ok来了，这个rdata给pfs，不是fs在fs_wait_data等的那条
    wire        pfs_inst_sram_data_ok;
    // fs有指令，但还不能往下送（fs_ready_go=0或ds_allowin=0），pfs不能发新请求
    wire        pfs_block;
    // 处理分支跳转，延迟槽处理完，pfs里跳转目标那条指令正要送进fs，用于清除br_bus缓存，表示跳转结束
    wire        target_leaving_pfs;
    // 延迟槽指令正要送进fs，下一拍可以改pc取target
    wire        bd_leaving_pfs;
    // 锁存id发来的跳转，id刚算出来br_taken_w=1，fs还没有锁存br_taken_w信号，这一拍要锁存br_bus
    wire        br_latch;
    // 例外码
    wire [4:0]  fs_exp;
    // 是否adel例外
    wire        fs_exp_adel;

    // pfs的组合信号
    // 要不要跳转，ds当拍组合输出分支；或者br_taken_r已经锁存有跳转
    assign br_taken  = br_taken_r || br_taken_w;
    // 跳到哪里，ds当拍输入的br_target_w或者锁存的br_target_r
    assign br_target = br_taken_r ? br_target_r : br_target_w;
    // 延迟槽inst已经进fs，pfs可以将pfs_pc跳转到br_target了，不用理会delay inst了
    assign bd_done   = bd_done_r || fs_valid;

    assign pfs_pc = (br_taken && bd_done) ? br_target : seq_pc;

    assign pfs_addr_ok           = (inst_sram_req && inst_sram_addr_ok) || pfs_addr_ok_r;
    assign pfs_ready_go          = pfs_addr_ok;
    assign pfs_to_fs_valid       = pfs_ready_go && ~ws_to_fs_excp && ~ws_to_fs_eret;
    assign pfs_inst_sram_data_ok = inst_sram_data_ok && fs_inst_unable;
    assign pfs_inst_ok           = pfs_inst_buff_valid ||
                                   (pfs_addr_ok && pfs_inst_sram_data_ok);

    assign pfs_inst              = pfs_inst_buff_valid ? pfs_inst_buff : inst_sram_rdata;

    // 为1，给pfs；为0，给fs
    // sram数据直接返回给fs的只有一种可能，即fs已经有了pc在等inst
    // 其他情况都是pfs给fs数据
    assign fs_inst_unable        = !fs_valid || pfs_inst_buff_valid || fs_ready_go;
    // pfs阻塞的唯一情况是fs有有效数据，且fs_allowin不让进
    assign pfs_block             = fs_valid && !fs_allowin;
    assign fs_inst               = fs_inst_r;
    assign fs_ready_go           = fs_valid && !fs_wait_data;
    // 这是判断fs_allowin的基本逻辑，要么fs_valid无效，fs可以让指令流入
    // 要么fs已经可以走了，且ds已经让走了，即下一拍fs一定会走，fs也可以让指令流入
    assign fs_allowin            = !fs_valid || (fs_ready_go && ds_allowin);
    // fs_valid有效，且fs可以走，则fs_to_ds_valid有效，这也是基本逻辑
    assign fs_to_ds_valid        = fs_valid && fs_ready_go && ~ws_to_fs_excp && ~ws_to_fs_eret;

    assign br_latch              = br_taken_w && !br_taken_r;
    assign target_leaving_pfs    = br_taken && pfs_to_fs_valid && fs_allowin && bd_done;
    assign bd_leaving_pfs        = br_taken && pfs_to_fs_valid && fs_allowin && !bd_done;


    assign inst_sram_req         = ~reset && !pfs_addr_ok_r && !pfs_block &&
                                   ~ws_to_fs_excp && ~ws_to_fs_eret;
    assign inst_sram_wr          = 1'b0;
    assign inst_sram_size        = 2'd2;
    assign inst_sram_wstrb       = 4'h0;
    assign inst_sram_addr        = {pfs_pc[31:2], 2'b0};
    assign inst_sram_wdata       = 32'b0;


    assign fs_exp                = (fs_pc[1:0] == 2'b00) ? 5'h1f : `EXP_ADEL;
    assign fs_exp_adel           = (fs_exp == `EXP_ADEL);

    assign fs_to_ds_bus          = { fs_exp_adel,
                                     fs_pc,
                                     fs_exp,
                                     fs_inst,
                                     fs_pc };

    // br_bus buffer
    // br_taken_r和br_target_r是ds发来的跳转信息在pfs的缓存，处理一拍跳转需要好几拍
    // 而br_bus是组合信号，分支离开ds就没了
    always @(posedge clk) begin
        if (reset) begin
            br_taken_r  <= 1'b0;
            br_target_r <= 32'b0;
        end
        // 跳转目标进入fs时，即target_leaving_pfs，或者异常、eret，两个reg清0
        else if (target_leaving_pfs || ws_to_fs_excp || ws_to_fs_eret) begin
            br_taken_r  <= 1'b0;
            br_target_r <= 32'b0;
        end
        else if (br_latch) begin
            br_taken_r  <= br_taken_w;
            br_target_r <= br_target_w;
        end
    end

    always @(posedge clk) begin
        if (reset)
            bd_done_r <= 1'b0;
        else if (target_leaving_pfs || ws_to_fs_excp || ws_to_fs_eret)
            bd_done_r <= 1'b0;
        else if (br_latch)
            bd_done_r <= fs_valid || (pfs_to_fs_valid && fs_allowin);
        else if (bd_leaving_pfs)
            bd_done_r <= 1'b1;
    end

    // seq_pc
    always @(posedge clk) begin
        if (reset)
            seq_pc <= 32'hbfc00000;
        else if (ws_to_fs_excp)
            seq_pc <= 32'hbfc00380;
        else if (ws_to_fs_eret)
            seq_pc <= ws_to_fs_pc;
        else if (pfs_to_fs_valid && fs_allowin)
            seq_pc <= pfs_pc + 32'h4;
    end

    // pre-IF addr_ok pending
    always @(posedge clk) begin
        if (reset)
            pfs_addr_ok_r <= 1'b0;
        // pfs的addr握手已经完成，但fs还不让传输，要把这个状态给记下来
        else if (inst_sram_req && inst_sram_addr_ok && !fs_allowin)
            pfs_addr_ok_r <= 1'b1;
        // fs能收，清掉pfs_addr_ok_r，而且不会出现fs_allowin有效，pfs_to_fs_valid无效的情况
        // 即，只要fs能收，pfs就一定能送
        // 异常时，清掉pfs_addr_ok_r,不能握着旧的pfs_addr_ok_r阻止发新req
        // eret同理
        else if (fs_allowin || ws_to_fs_excp || ws_to_fs_eret)
            pfs_addr_ok_r <= 1'b0;
    end

    // pre-IF inst buffer
    // 只要fs_allowin，则rdata就直接给了fs
    always @(posedge clk) begin
        if (reset) begin
            pfs_inst_buff_valid <= 1'b0;
            pfs_inst_buff       <= 32'b0;
            pfs_pc_buff         <= 32'b0;
        end
        else if (fs_allowin || ws_to_fs_excp || ws_to_fs_eret) begin
            pfs_inst_buff_valid <= 1'b0;
            pfs_inst_buff       <= 32'b0;
            pfs_pc_buff         <= 32'b0;
        end
        else if (pfs_addr_ok && pfs_inst_sram_data_ok && !fs_allowin) begin
            pfs_inst_buff_valid <= 1'b1;
            pfs_inst_buff       <= inst_sram_rdata;
            pfs_pc_buff         <= pfs_pc;
        end
    end

    // IF valid / bus
    always @(posedge clk) begin
        if (reset)
            fs_valid <= 1'b0;
        // 发生例外或者eret时，fs正在取的inst不能往下走，pc会跳到异常入口或者eret目标
        // 要把fs清空，后面从新pc取指
        else if (ws_to_fs_excp || ws_to_fs_eret)
            fs_valid <= 1'b0;
        else if (fs_allowin)
            fs_valid <= pfs_to_fs_valid;
    end

    always @(posedge clk) begin
        if (reset)
            fs_pc <= 32'b0;
        else if (pfs_to_fs_valid && fs_allowin)
            // fs_to_ds_bus会在同一个clk上升沿更新，因为fs_to_ds_bus是组合逻辑
            // 同样的在ds中的fs_to_ds_bus输入也是同一个clk上升沿更新
            fs_pc <= pfs_inst_buff_valid ? pfs_pc_buff : pfs_pc;
    end

    always @(posedge clk) begin
        if (reset)
            fs_wait_data <= 1'b0;
        else if (ws_to_fs_excp || ws_to_fs_eret)
            fs_wait_data <= 1'b0;
        else if (pfs_to_fs_valid && fs_allowin)
            fs_wait_data <= ~pfs_inst_ok;
        // 这里fs_wait_data用的是旧值，即旧值为1，且data_ok，则新值赋值为0
        else if (fs_wait_data && inst_sram_data_ok)
            fs_wait_data <= 1'b0;
    end

    always @(posedge clk) begin
        if (reset)
            fs_inst_r <= 32'b0;
        // 异常或者eret时指令清0，同时valid无效，则这条0指令不会往后传
        else if (ws_to_fs_excp || ws_to_fs_eret)
            fs_inst_r <= 32'b0;
        // 取指时addr和data一起到位，或data已经在pfs_inst_buff，送入fs时pc和inst同时写入
        else if (pfs_to_fs_valid && fs_allowin && pfs_inst_ok)
            // pfs_inst自来buffer或者当拍SRAM的rdata
            fs_inst_r <= pfs_inst;
        // fs已经在等待，先进fs的是pc，data晚几拍进入，同时fs_wait_data清0，fs才ready
        // 清fs_wait_data见line233
        else if (fs_wait_data && inst_sram_data_ok)
            fs_inst_r <= inst_sram_rdata;
    end

    always @(posedge clk) begin
        if (reset)
            IF_over <= 1'b0;
        else
            // 分支inst在ds的时候，看到if_over有效意味着fs传到ds的bus上的pc是延迟槽pc
            // 分支inst的branch target是依靠延迟槽pc计算的
            IF_over <= fs_valid;
    end

endmodule
