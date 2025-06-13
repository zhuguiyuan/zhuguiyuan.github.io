---
date: 2025-06-01
categories:
  - HW
---

# SystemVerilog 练习

前两天看完了《使用 SystemVerilog 进行 RTL 建模》这本书，算是第一次系统地学了一遍。最近也回顾了刚上研究生时候写的 EE218-VLSI 课程项目，觉得可以用 SystemVerilog 重写一遍作为练习。于是在这里记录下项目规约和实现。

<!-- more -->

## 项目规约

实现一个 MLP 单元，这个单元有 8 层，每层 16 * 16 的权重（$W_0 ... W_7$），接收一个 16 * 16 的输入 $I$，计算 $W_7 \times ... \times W_0 \times I$。

端口定义为：

- `start_ready`，1 位输出，表示模块准备好，可以加载输入并开始一轮计算任务
- `start_valid`，1 位输入，表示启动计算任务，在之后（从下一个周期开始）16 * 16 个周期顺序加载输入矩阵 $I$，然后开始计算
- `init_ready`，1 位输出，表示模块准备好，可以加载权重
- `init_valid`，1 位输入，表示启动权重加载，在之后（从下一个周期开始）16 * 16 * 8 个周期顺序加载权重 $W_0 ... W_7$
- `load_payload`，16 位输入，用于加载输入和权重矩阵
- `result_valid`，1 位输出，表示当前周期输出的数据有效
- `result_payload`，16 位输出，表示 MLP 输出的计算结果


其他要求为：

- 所有的输入和输出都是 16 位定点数（7 位整数，9 位小数）。中间计算步骤需要保证全精度，结果先对小数部分使用就近四舍五入，然后对整数部分使用饱和操作处理溢出。
- 输入和输出带宽不超过 32 bits 每 cycle。
- 提供了字宽为 16 和 32 的，深度为 128、256、512 和 1024 的，单端口和伪双端口的 SRAM 硬核，及相应的 RTL 行为模型。

RTL 行为模型如下两个例子所示，其他 RAM 实例的名称和位宽自行类比：
```verilog
// 深度 1024 字宽 32 伪双端口
module sramTpw1024d32 (
    input  wire [31:0] D,
    input  wire [ 9:0] ADRw,
    input  wire        MEw,
    output wire [31:0] Q,
    input  wire [ 9:0] ADRr,
    input  wire        MEr,
    input  wire        clk
);
  reg [31:0] tmp_Q;
  reg [31:0] sramTp[0:1023];

  always @(posedge clk) begin
    if (MEw) begin
      sramTp[ADRw] <= D;
    end
    if (MEr) begin
      tmp_Q <= sramTp[ADRr];
    end
  end

  assign Q = tmp_Q;

endmodule

// 深度 128 字宽 32 单端口
module sramSpw128d32 (
    output wire [31:0] Q,
    input  wire [ 6:0] ADR,
    input  wire [31:0] D,
    input  wire        WE,
    input  wire        ME,
    input  wire        clk
);
  reg [31:0] tmp_Q;
  reg [31:0] sramSp[0:127];

  always @(posedge clk) begin
    if (ME) begin
      tmp_Q <= sramSp[ADR];
    end
    if (ME && WE) begin
      sramSp[ADR] <= D;
    end
  end

  assign Q = tmp_Q;

endmodule
```

项目提供了一些测试数据，由于以练习 SystemVerilog 为目的，只实现 RTL 模型即可，不用做后端。使用 Icarus Verilog 和 ADM/Xilinx Vivado 分别作为开源和闭源的仿真工具。使用 [Yosys-STA](https://github.com/zhuguiyuan/Yosys-STA) 项目评估时序。

## 项目实现

代码见仓库 [SystemVerilog-Exercise](https://github.com/zhuguiyuan/SystemVerilog-Exercise)。
