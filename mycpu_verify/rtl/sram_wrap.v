/*------------------------------------------------------------------------------
--------------------------------------------------------------------------------
Copyright (c) 2016, Loongson Technology Corporation Limited.

All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this 
list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, 
this list of conditions and the following disclaimer in the documentation and/or
other materials provided with the distribution.

3. Neither the name of Loongson Technology Corporation Limited nor the names of 
its contributors may be used to endorse or promote products derived from this 
software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
DISCLAIMED. IN NO EVENT SHALL LOONGSON TECHNOLOGY CORPORATION LIMITED BE LIABLE
TO ANY PARTY FOR DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE 
GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) 
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT 
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--------------------------------------------------------------------------------
------------------------------------------------------------------------------*/
//for func test, no define RUN_PERF_TEST(运行优先测试)
`define _RUN_PERF_TEST

module sram_wrap(
  input         clk,
  input         resetn,

  input         req    , // 请求信号，1为有读写请求；0为无读写请求
  input         wr     , // 1为写请求；0为读请求
  input [1 :0]  size   , // 请求传输字节数：0为1B；1为2B；2为4B
  input [3 :0]  wstrb  , // 写请求的字节写使能
  input [31:0]  addr   , // 请求的地址
  input [31:0]  wdata  , // 写请求的写数据

  // 给上一模块（cpu core）
  output        addr_ok, // 该次请求地址传输OK，读：地址被接收；写：地址和数据被接收
  output        data_ok, // 该次请求数据传输OK，读：数据返回；写：数据写入完成
  output [31:0] rdata  , // 读请求返回的读数据

  //slave，给ram模块
  output        ram_en   ,
  output [3 :0] ram_wen  ,
  output [31:0] ram_addr ,
  output [31:0] ram_wdata,
  input  [31:0] ram_rdata,

  //from confreg(配置寄存器)
  input  [1 :0] ram_random_mask
);
//mask
`ifdef RUN_PERF_TEST
    assign addr_and = 1'b1;
    assign data_and = 1'b1;
`else
    assign addr_and = ram_random_mask[1];
    assign data_and = ram_random_mask[0];
`endif

//to ram
//size_decode是为了筛选出写入哪个字节
wire [3:0] size_decode = size==2'd0 ? {addr[1:0]==2'd3,addr[1:0]==2'd2,addr[1:0]==2'd1,addr[1:0]==2'd0} :
                         size==2'd1 ? {addr[1],addr[1],~addr[1],~addr[1]} :
                                      4'hf;

// 类SRAM接口从端：同一时刻只允许存在一个未完成(outstanding)的请求。
// 这样读/写不会互相干扰，data_ok 严格按请求顺序返回，避免写请求把陈旧的
// ram读数据压入读数据缓冲、或抢占读数据 data_ok 等错误。
// addr_ok 受 addr_and 随机掩码控制(地址相随机延迟)；
// data_ok 受 data_and 随机掩码控制(数据相随机延迟)，并在 data_and=0 时保持，
// 直到 data_and=1 才真正返回给上级。
reg busy;        // 当前存在一个未完成的请求(addr_ok已接受, data_ok未返回)
reg ram_done;    // ram访问已完成(读数据已就绪/写已完成)，保持到 data_ok 返回
reg ram_en_r;    // ram_en 的打一拍，标志本拍ram访问完成

assign addr_ok   = addr_and && !busy;
assign ram_en    = req && addr_ok;
assign ram_wen   = {4{wr}} & wstrb & size_decode;
assign ram_addr  = addr;
assign ram_wdata = wdata;

always @(posedge clk) begin
    if(!resetn) begin
        ram_en_r <= 1'b0;
        busy     <= 1'b0;
        ram_done <= 1'b0;
    end
    else begin
        ram_en_r <= ram_en;

        // busy: 接受新请求时置1, data_ok 返回时清0
        if (req && addr_ok)
            busy <= 1'b1;
        else if (data_ok)
            busy <= 1'b0;

        // ram_done: 接受新请求时清0, ram访问完成(ram_en_r)时置1并保持,
        // 直到下一次接受新请求才复位
        if (req && addr_ok)
            ram_done <= 1'b0;
        else if (ram_en_r)
            ram_done <= 1'b1;
    end
end

//data_ok: ram访问完成且 data_and 允许时返回
assign data_ok = data_and && busy && (ram_en_r || ram_done);
//rdata: 读数据, ram_rdata在busy期间保持(ena=0, 同步ram输出寄存器不更新)
assign rdata   = ram_rdata;

endmodule
