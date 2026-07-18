---
title: LLVMlite 文档
date: 2025-06-13
taxon: PL
---

LLVMlite 是 Upenn CIS314（也是上科大 CS131）Compiler 课程中定义的 LLVM IR 的简化子集。它保留了 LLVM 的核心要素，挺适合用作初学者写编译器的目标语言。这篇文章是 LLVMlite 规范的简要记录。

## 第一感觉

下面是 LLVMlite 的一个例子，可以看到一些基本元素和 LLVM 是一致的。

这个例子也能通过 `llc` 编译为 ISA 对应的汇编或 `clang` 直接编译为可以运行的 ELF。

```bash
clang demo.ll -o demo && ./demo && echo $?
```

可以得到结果是 208（在 Bash 中返回值是 uint8_t，fac(6) = 720 截断之后就是 208）。

```llvm
; demo.ll
define i64 @fac(i64 %n) {              ; (1)
  %1 = icmp sle i64 %n, 0              ; (2)
  br i1 %1, label %ret, label %rec     ; (3)
ret:                                   ; (4)
  ret i64 1
rec:                                   ; (5)
  %2 = sub i64 %n, 1                   ; (6)
  %3 = call i64 @fac(i64 %2)           ; (7)
  %4 = mul i64 %n, %3
  ret i64 %4                           ; (8)
}

define i64 @main() {                   ; (9)
  %1 = call i64 @fac(i64 6)
  ret i64 %1
}
```

全局变量名以 `@` 开始，局部变量名以 `%` 开始，类型别名以 `%` 开始。函数定义 `define` 和各种指令（`icmp sle`、`sub`、`call`）都带类型。整体来说是和 C 差不多的弱类型，即有基本的类型检查，但是可以用 `bitcast` 指令强制转换。

## 数据类型

数据类型整体上可以分为单元类型、简单类型、聚合类型和函数类型，具体语法如下所示：

| 具体语法 | 种类 | 说明 |
|---|---|---|
| `void` | 单元类型 | 就是 OCaml 里的 `unit`，注意不是 Java 的 `null` |
| `i1`，`i8`，`i64` | 简单类型 | 表示固定宽度的整数，LLVMlite 限制了只有这三种，LLVM 没有宽度限制 |
| `T*` | 简单类型 | 指向类型 `T` 的指针类型 |
| `F*` | 简单类型 | 指向函数 `F` 的指针类型 |
| `S(S1, ... SN)` | 函数类型 | 参数为 `S1` 到 `SN`，返回值为 `S` 的函数 |
| `{ T1, ..., TN }` | 聚合类型 | 类型 `T1` 到 `TN` 构成的元组 |
| `[ N x T ]` | 聚合类型 | `N` 个 `T` 类型构成的数组 |
| `%NAME` | * | 命名类型定义，也就是给某个类型取的别名 |

其中命名类型定义的具体语法是 `%IDENT = type T`，`T` 中可以提到 `%IDENT`，但是不允许循环类型，也就是说如果提到 `%IDENT` 则必须出现在指针 `*` 下。

下面是对应的 OCaml ADT 表示

```ocaml
(* Local identifiers *)
type uid = string

(* Global identifiers *)
type gid = string

(* Named types *)
type tid = string

(* LLVM types *)
type ty =
| Void
| I1
| I8
| I64
| Ptr of ty
| Struct of ty list
| Array of int * ty
| Fun of ty list * ty
| Namedt of tid
```

有一个需要注意的点：LLVMlite 规定只有简单类型才可以出现在栈中或者是作为函数的参数，而聚合类型只能出现在全局和（运行时分配的）堆内存中，在栈上只能存一个指针。也就是说，简单类型可以 `alloca` 但是聚合类型不能 `alloca`（这一点和完整的 LLVM 不一样，完整的 LLVM 是可以 `alloca` 一个聚合类型的）。这个限制是简化目的，对于所有的聚合类型就要在运行时实现一个 `malloc` 之类的函数来处理分配了；结构体也不能像 C 语言那样整个拷贝传值调用，而是只能传一个指针。

## 程序结构

LLVMlite 程序由（1）全局函数声明；（2）全局数据声明；（3）类型别名声明；（4）外部符号声明四部分构成。所有顶层定义都是互递归的。下面是这四部分的 OCaml 数据结构。这里我们关注 `prog` 这个类型，是把顶层声明的绑定到名字上，有点像是可以创造出一个 ctxt 之类的东西用来做查询（实际上 LLVMlite 编译到 ISA 的时候也的确会用到）。

```ocaml
(* Function type: argument types and return type *)
type fty = ty list * ty

(* Control Flow Graphs: entry and labeled blocks *)
type cfg = block * (lbl * block) list

(* Function Declarations *)
type fdecl = { f_ty : fty; f_param : uid list; f_cfg : cfg }

(* Global Data Initializers *)
type ginit =
| GNull
| GGid of gid
| GInt of int64
| GString of string
| GArray of (ty * ginit) list
| GStruct of (ty * ginit) list
| GBitcast of ty * ginit * ty

(* Global Declarations *)
type gdecl = ty * ginit

(* LLVMlite Programs *)
type prog = { tdecls : (tid * ty) list;
              gdecls : (gid * gdecl) list;
              fdecls : (gid * fdecl) list;
              edecls : (gid * ty) list }
```

下面我们依次关注 `prog` 的各个字段。

## 类型别名声明

`{ tdelcs : (tid * ty) list; ... }` 是把类型绑定到一个 tid 上。具体语法如下所示：

```llvm
%foo = type i64
%bar = type [ 8 x i64 ]
```

假设上层语言有一个 `typealis Foo = Bar` 之类的代码，我们可以编译成一个 `[ "Foo", cmp_ty (Namedt "Bar") ]` 把右边编译好的类型绑定到 `"Foo"` 这个名字上。

## 外部符号声明

`{ edecls: (gid * ty) list; ... }` 在 LLVMlite 中的具体语法有下面的例子：

```llvm
declare i32 @puts(i8*)
declare i32 @some_extern_func(i32, [5 x i64], i8*)
```

可以用来编译上层语言的外部声明之类。也可以用来声明上层语言的内建函数，实现可以放到运行时里面用其他语言来生成，只要链接时对上签名 ABI 就行。

## 全局数据声明

`{ gdecls: (gid * gdecl) list; ... }`，然后回顾一下 `gdecl` 的类型是 `type gdecl = ty * ginit`，也就是类型及其初始值。`ty` 和 `ginit` 需要手动对上，后者有下面的几种可能：

```ocaml
(* Global Data Initializers *)
type ginit =
| GNull
| GInt of int64
| GString of string
| GGid of gid
| GArray of (ty * ginit) list
| GStruct of (ty * ginit) list
| GBitcast of ty * ginit * ty
```

全局声明的具体语法是：

```llvm
@foo = global i64 42
@bar = global i64* @foo
@baz = global i64** @bar
```

下面的表列出了各种 `ginit` 的具体语法：

| 具体语法 | 类型 | 说明 |
|---|---|---|
| `null` | `T*` | 空指针常量 |
| `[0-9]+` | `i64` | 64 位有符号整数字面量 |
| `c"[A-z]*\00"` | `[N x i8]` | 字符串字面量，长度 `N` 包括结尾的空字符 |
| `@IDENT` | `T*` | 全局标识符，注意始终是指针 |
| `[ T G1, ..., T GN ]` | `[ N x T ]` | 数组字面量 |
| `{ T1 G1, ..., TN GN }` | `{ T1,...,TN }` | 结构体字面量 |
| `bitcast (T1* G1 to T2*)` | `T2*` | 重新解释比特的类型 |

## 全局函数声明

`{ fdecls: (gid * fdecl) list; ... }`，其中 `type fdecl = { f_ty : fty; f_param : uid list; f_cfg : cfg }`。函数声明的具体语法如下所示：

```llvm
define i64 @fac(i64 %n) {
  %1 = icmp sle i64 %n, 0
  br i1 %1, label %ret, label %rec
ret:
  ret i64 1
rec:
  %2 = sub i64 %n, 1
  %3 = call i64 @fac(i64 %2)
  %4 = mul i64 %n, %3
  ret i64 %4
}
```

函数内部是由基本块组成的。每个基本块（除了函数的第一个基本块）开头都有一个标签，内部都是普通指令，没有跳转指令，最后是一条跳转指令。

在 LLVMlite 中要求第一个基本块没有标签，在 LLVM 中第一个基本块的标签是可选的，如果没有写的话会默认分配一个标签。

指令的操作数如下所示：

| 具体语法 | 类型 | 描述 |
|---|---|---|
| `null` | `T*` | 空指针常量 |
| `[0-9]+` | `i64` | 64 位整数字面量 |
| `@IDENT` | `T*` | 全局标识符，注意始终是指针 |
| `%IDENT` | `S` | 局部标识符，只能是简单类型的值 |

对应的 OCaml 语法是：

```ocaml
(* Syntactic Values *)
type operand =
| Null
| Const of int64
| Gid of gid
| Id of uid
```

基本指令包括：

| 具体语法 | 操作数 → 结果类型 |
|---|---|
| `%L = BOP i64 OP1, OP2` | `i64 x i64 -> i64` |
| `%L = alloca S` | `- -> S*` |
| `%L = load S* OP` | `S* -> S` |
| `store S OP1, S* OP2` | `S x S* -> void` |
| `%L = icmp CND S OP1, OP2` | `S x S -> i1` |
| `%L = call S1 OP1(S2 OP2, ..., SN OPN)` | `S1(S2, ..., SN)* x S2 x ... x SN -> S1` |
| `call void OP1(S2 OP2, ... ,SN OPN)` | `void(S2, ..., SN)* x S2 x ... x SN -> void` |
| `%L = getelementptr T1, T1* OP1, i32 OP2, ..., i32 OPN` | `T1* x i64 x ... x i64 -> GEPTY(T1, OP1, ..., OPN)*` |
| `%L = bitcast T1* OP to T2*` | `T1* -> T2*` |

基本指令的 OCaml 表示如下所示：

```ocaml
(* Instructions *)
type insn =
| Binop of bop * ty * operand * operand
| Alloca of ty
| Load of ty * operand
| Store of ty * operand * operand
| Icmp of cnd * ty * operand * operand
| Call of ty * operand * (ty * operand) list
| Bitcast of ty * operand * ty
| Gep of ty * operand * operand list
```

（`Load` 的 `ty` 指的是 `S*`；`Store` 的 `ty` 是 `S`，第一个 `operand` 存到第二个 `operand` 里；`Bitcase` 是左边的 `ty` cast 成右边的 `ty`）

终结指令包容：

| 具体语法 | 操作数 → 结果类型 |
|---|---|
| `ret void` | `- -> -` |
| `ret S OP` | `S -> -` |
| `br label %LAB` | `- -> -` |
| `br i1 OP, label %LAB1, label %LAB2` | `i1 -> -` |

终结指令的 OCaml 表示如下所示：

```ocaml
type terminator =
| Ret of ty * operand option
| Br of lbl
| Cbr of operand * lbl * lbl
```

## 关于 SSA

目前 LLVMlite 里面还没有引入 `phi` 语句，因此要处理上层语言 mutable 的情况，只能用 `alloca` 和 `store` 开洞。但是这个问题不大，因为生成的 LLVMlite 代码和 LLVM 是兼容的，当作 LLVM 走一下 `opt` 就优化成带有 phi 节点了，然后就可以做 SSA 的优化和生成。
