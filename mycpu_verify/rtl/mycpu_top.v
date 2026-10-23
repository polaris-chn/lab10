`include "mycpu.h"

module mycpu_top(
    input         clk,
    input         resetn,

    // inst sram interface
    output        inst_sram_req,
    output        inst_sram_wr,
    output [ 1:0] inst_sram_size,
    output [ 3:0] inst_sram_wstrb,
    output [31:0] inst_sram_addr,
    output [31:0] inst_sram_wdata,
    input         inst_sram_addr_ok,
    input         inst_sram_data_ok,
    input  [31:0] inst_sram_rdata,

    // data sram interface
    output        data_sram_req,
    output        data_sram_wr,
    output [ 1:0] data_sram_size,
    output [ 3:0] data_sram_wstrb,
    output [31:0] data_sram_addr,
    output [31:0] data_sram_wdata,
    input         data_sram_addr_ok,
    input         data_sram_data_ok,
    input  [31:0] data_sram_rdata,


    // trace debug interface
    output [31:0] debug_wb_pc,
    output [ 3:0] debug_wb_rf_wen,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata

    // input         open_trace
);
    reg         reset;
    always @(posedge clk) 
        reset <= ~resetn;

    wire        ds_allowin;
    wire        es_allowin;
    wire        ms_allowin;
    wire        ws_allowin;
    wire        fs_to_ds_valid;
    wire        ds_to_es_valid;
    wire        es_to_ms_valid;
    wire        es_to_ms_wants;
    wire        es_incoming_mem;
    wire        ms_to_ws_valid;
    wire        IF_over;

    wire [`FS_TO_DS_BUS_WD -1:0]        fs_to_ds_bus;
    wire [`DS_TO_ES_BUS_WD -1:0]        ds_to_es_bus;
    wire [`ES_TO_MS_BUS_WD -1:0]        es_to_ms_bus;
    wire [`MS_TO_WS_BUS_WD -1:0]        ms_to_ws_bus;
    wire [`WS_TO_RF_BUS_WD -1:0]        ws_to_rf_bus;
    wire [`BR_BUS_WD       -1:0]        br_bus;
    wire [31:0]                         ws_to_fs_pc;

    wire [`ES_TO_DS_FORWARD_BUS -1:0]   es_to_ds_forward_bus;
    wire [`MS_TO_DS_FORWARD_BUS -1:0]   ms_to_ds_forward_bus;
    wire [`WS_TO_DS_FORWARD_BUS -1:0]   ws_to_ds_forward_bus;

    wire        ws_forward_excp;
    wire        ws_forward_eret;
    wire        ms_to_es_excp;
    wire        ms_to_es_eret;
    wire        ms_to_es_handoff;

    // IF stage
    wire        fs_to_if_excp;
    assign      fs_to_if_excp = ws_forward_excp;
    if_stage if_stage(
        .clk            (clk            ),
        .reset          (reset          ),
        .ds_allowin     (ds_allowin     ),
        .br_bus         (br_bus         ),
        .ws_to_fs_excp  (fs_to_if_excp  ),
        .ws_to_fs_eret  (ws_forward_eret  ),
        .ws_to_fs_pc    (ws_to_fs_pc    ),
        .fs_to_ds_valid (fs_to_ds_valid ),
        .fs_to_ds_bus   (fs_to_ds_bus   ),

        // inst sram interface
        .inst_sram_req      (inst_sram_req      ),
        .inst_sram_wr       (inst_sram_wr       ),
        .inst_sram_size     (inst_sram_size     ),
        .inst_sram_wstrb    (inst_sram_wstrb    ),
        .inst_sram_addr     (inst_sram_addr     ),
        .inst_sram_wdata    (inst_sram_wdata    ),
        .inst_sram_addr_ok  (inst_sram_addr_ok  ),
        .inst_sram_data_ok  (inst_sram_data_ok  ),
        .inst_sram_rdata    (inst_sram_rdata    ),


        .IF_over            (IF_over            )
    );


    // ID stage
    id_stage id_stage(
        .clk                    (clk            ),
        .reset                  (reset          ),
        .es_allowin             (es_allowin     ),
        .ds_allowin             (ds_allowin     ),
        .fs_to_ds_valid         (fs_to_ds_valid ),
        .fs_to_ds_bus           (fs_to_ds_bus   ),
        .ds_to_es_valid         (ds_to_es_valid ),
        .ds_to_es_bus           (ds_to_es_bus   ),
        .br_bus                 (br_bus         ),
        .ws_to_rf_bus           (ws_to_rf_bus   ),
        .IF_over                (IF_over        ),
        
        .es_to_ds_forward_bus   (es_to_ds_forward_bus),
        .ms_to_ds_forward_bus   (ms_to_ds_forward_bus),
        .ws_to_ds_forward_bus   (ws_to_ds_forward_bus),
        .ws_to_ds_excp          (ws_forward_excp),
        .ws_to_ds_eret          (ws_forward_eret)
    );


    // EXE stage
    exe_stage exe_stage(
        .clk                    (clk            ),
        .reset                  (reset          ),
        .ms_allowin             (ms_allowin     ),
        .es_allowin             (es_allowin     ),
        .ds_to_es_valid         (ds_to_es_valid ),
        .ds_to_es_bus           (ds_to_es_bus   ),
        .es_to_ms_valid         (es_to_ms_valid ),
        .es_to_ms_wants         (es_to_ms_wants ),
        .es_incoming_mem         (es_incoming_mem ),
        .es_to_ms_bus           (es_to_ms_bus   ),

        // data sram interface
        .data_sram_req          (data_sram_req      ),
        .data_sram_wr           (data_sram_wr       ),
        .data_sram_size         (data_sram_size     ),
        .data_sram_addr         (data_sram_addr     ),
        .data_sram_wstrb        (data_sram_wstrb    ),
        .data_sram_wdata        (data_sram_wdata    ),
        .data_sram_addr_ok      (data_sram_addr_ok  ),

        .es_to_ds_forward_bus   (es_to_ds_forward_bus),
        .ws_to_es_excp          (ws_forward_excp),
        .ws_to_es_eret          (ws_forward_eret),
        .ms_to_es_excp          (ms_to_es_excp  ),
        .ms_to_es_eret          (ms_to_es_eret  ),
        .ms_to_es_handoff       (ms_to_es_handoff)
    );


    // MEM stage
    mem_stage mem_stage(
        .clk                    (clk            ),
        .reset                  (reset          ),
        .ws_allowin             (ws_allowin     ),
        .ms_allowin             (ms_allowin     ),
        .es_to_ms_valid         (es_to_ms_valid ),
        .es_to_ms_wants         (es_to_ms_wants ),
        .es_incoming_mem         (es_incoming_mem ),
        .es_to_ms_bus           (es_to_ms_bus   ),
        .ms_to_ws_valid         (ms_to_ws_valid ),
        .ms_to_ws_bus           (ms_to_ws_bus   ),
        .ws_to_ms_excp          (ws_forward_excp),
        .ws_to_ms_eret          (ws_forward_eret),
        .ms_to_es_excp          (ms_to_es_excp  ),
        .ms_to_es_eret          (ms_to_es_eret  ),
        .ms_to_es_handoff       (ms_to_es_handoff),

        //from data-sram
        .data_sram_addr_ok      (data_sram_addr_ok  ),
        .data_sram_data_ok      (data_sram_data_ok  ),
        .data_sram_rdata        (data_sram_rdata    ),


        .ms_to_ds_forward_bus   (ms_to_ds_forward_bus)
    );


    // WB stage
    wb_stage wb_stage(
        .clk                    (clk            ),
        .reset                  (reset          ),
        .ws_allowin             (ws_allowin     ),
        .ms_to_ws_valid         (ms_to_ws_valid ),
        .ms_to_ws_bus           (ms_to_ws_bus   ),

        //to rf: for write back
        .ws_to_rf_bus           (ws_to_rf_bus     ),
        .ws_forward_excp        (ws_forward_excp  ),
        .ws_forward_eret        (ws_forward_eret  ),
        .has_intr_out           (                 ),
        .ws_to_fs_pc            (ws_to_fs_pc      ),

        //trace debug interface
        .debug_wb_pc            (debug_wb_pc      ),
        .debug_wb_rf_wen        (debug_wb_rf_wen  ),
        .debug_wb_rf_wnum       (debug_wb_rf_wnum ),
        .debug_wb_rf_wdata      (debug_wb_rf_wdata),
        
        .ws_to_ds_forward_bus   (ws_to_ds_forward_bus)
    );

endmodule
