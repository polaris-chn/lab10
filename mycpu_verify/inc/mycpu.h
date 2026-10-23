`ifndef MYCPU_H
    `define MYCPU_H

    `define BR_BUS_WD       33
    `define FS_TO_DS_BUS_WD 64+5+32+1
    `define DS_TO_ES_BUS_WD 156+5+5+6+1+4+5+1+32+1+1
    `define ES_TO_MS_BUS_WD 213+5+5+6+4+5+1+32+1+1
    `define MS_TO_WS_BUS_WD 70+5+5+6+5+1+32+1+1
    `define WS_TO_RF_BUS_WD 38

    `define ES_TO_DS_FORWARD_BUS 39
    `define MS_TO_DS_FORWARD_BUS 39
    `define WS_TO_DS_FORWARD_BUS 39

    `define CR_INDEX    0
    `define CR_ENTRYLO0 1
    `define CR_ENTRLLO1 3
    `define CR_BADVADDR 8
    `define CR_COUNT    9
    `define CR_ENTRYHI  10
    `define CR_COMPARE  11
    `define CR_STATUS   12
    `define CR_CAUSE    13
    `define CR_EPC      14
    `define CR_CONFIG   16
    `define CR_CONFIG1  16

    `define EXP_INT     5'h00
    `define EXP_ADEL    5'h04
    `define EXP_ADES    5'h05
    `define EXP_SYS     5'h08
    `define EXP_BP      5'h09
    `define EXP_RI      5'h0a
    `define EXP_OV      5'h0c
`endif
