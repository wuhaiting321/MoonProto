# MoonProto

**纯 MoonBit 实现的 Protocol Buffers v3 Wire Format 编解码器，零 FFI、零代码生成。**

一份源码直接面向 Protobuf 字节流，提供增量式 `Encoder` / `Decoder`、全部 14 种标量类型、
packed repeated、嵌套消息与 group 安全跳过；不解析 `.proto`、不生成代码、不依赖
`protoc`，可在 WASI 沙箱内不请求任何宿主能力地独立运行。

[![CI](https://github.com/wuhaiting321/MoonProto/actions/workflows/ci.yml/badge.svg)](https://github.com/wuhaiting321/MoonProto/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](./LICENSE)

---

## 一、项目基本信息

| 项目 | 内容 |
| --- | --- |
| 项目名称 | MoonProto |
| 参赛者 | 吴海婷 |
| 联系方式 | 19177746962@163.com |
| GitHub 仓库 | <https://github.com/wuhaiting321/MoonProto> |
| 项目方向 | 序列化与数据交换基础库 / Protocol Buffers v3 Wire Format |
| 是否为移植项目 | 否，原创项目 |
| 模块名 | `wuhaiting321/moonproto`（遵循 mooncakes.io 的 `<author>/<module>` 命名规范） |
| 代码规模 | 1296 行库源码 + 2235 行测试 + 332 行可运行示例，27 个 `.mbt` 文件，合计 3863 行 |
| 测试状态 | `moon test` 全部通过（109 个用例，0 失败） |
| 构建状态 | 默认目标与 `moon check --target all --deny-warn` 均零错误、零告警；`moon fmt --check` 通过 |
| 开源许可证 | Apache-2.0 |

## 二、项目简介

Protocol Buffers 是 RPC、遥测、移动端持久化与设备通信的事实标准，而它的核心只有一套
**wire format**：字段号与 wire type 打包成 varint tag，标量按 varint / fixed / length-delimited
三种方式承载，嵌套消息与 packed 数组再用长度前缀切出边界。凡是要处理"别人发来的字节"
的场景——网关、调试器、协议转换、日志解析、WASI 插件——都需要一个可独立使用的 wire 层。

**MoonBit 生态现有 protobuf 能力以"schema → 代码生成"为入口。** 官方栈
`moonbitlang/protobuf` 配合 `protoc-gen-mbt`，为 `.proto` 生成的静态消息类型提供运行时；
社区项目 `moon_proto` 定位为围绕官方栈的 schema 验证与兼容性检查工具，`MoonPack`
则是借鉴 protobuf 思路、但不追求 protoc 兼容的 MoonBit 优先格式。它们解决的是
"如何从 schema 得到类型安全的代码/工具链"，而不是"手上只有一串 wire bytes 时如何
动态地逐字段读写"。

**MoonProto 用于补齐这一层空白。** 它不做 `.proto` 解析，也不生成任何代码，而是把
wire format 的每个原语（varint、zigzag、tag、长度窗口、标量、packed、嵌套消息、group）
直接暴露给调用方：字段号与值类型由调用方在运行时给出，解码器逐字段推进，任何越界、
截断、非法编码都以带绝对偏移的具名错误返回。因此它既可作为手写协议代码的底座，
也可作为协议调试、模糊测试与教学工具使用。

**与现有能力的本质区别**

- 与官方 protobuf 运行时相比：官方栈服务的是生成后的静态消息；MoonProto 提供
  **无 schema、无生成步骤**的动态标量 API，适合协议探测、转换层与测试工具。
  两者不是替代关系：生成的代码同样需要一个可靠的 wire 层，MoonProto 可以作为其底层原语。
- 与 FFI 封装相比：不链接 C/Rust 的 protobuf 库，不出现 `extern "c"`，只依赖
  `moonbitlang/core`，产物可直接放进 WASI 沙箱，宿主无需提供 protoc 或系统库。
- 与"只解不编"的示例代码相比：编码与解码共享同一套标量表与 wire type 校验，
  测试用编码→解码往返与已知向量双向验证，而不是只跑通一个方向。
- 与 schema 工具链相比：不引入 `protoc`、descriptor 或反射层，调用方对字段号的
  选择就是唯一事实来源，边界与错误路径因此可以在 1296 行内被完整审计。

## 三、典型使用场景

三个场景分别由三个独立可执行包实现，各有自己的业务域、字段约定与真实输出：

| 场景 | 示例包 | 业务域 | 主要能力 |
| --- | --- | --- | --- |
| 3.1 设备遥测批量上报 | [examples/telemetry](./examples/telemetry/main.mbt) | 物联网遥测 | 多标量、packed repeated、采样聚合 |
| 3.2 聊天消息解析与前向兼容 | [examples/chat](./examples/chat/main.mbt) | 即时通讯 | 嵌套消息、bytes、未知字段跳过 |
| 3.3 协议调试与畸形输入定位 | [examples/basic](./examples/basic/main.mbt) | 协议调试 | 编解码往返、异常偏移定位 |

所有示例只读取内嵌字节，不读取文件、不请求宿主能力。

### 3.1 设备遥测批量上报（边缘网关 → 云端）

- **业务背景**：设备把一批传感器采样批量上报，云端没有 `.proto`，只凭字段号解析。
- **字段约定**：1 `string device_id`；2 `uint64 collected_at_ms`；
  3 `double temperature_c`；4 `uint32 battery_mv`；5 `enum status`；
  6 `packed sint32 samples`
- **调用**：`write_string`、`write_scalar_field`（UInt64 / Double / UInt32 / Enum）、
  `write_packed_scalar_field`；云端用 `read_packed_scalar_field` 取回采样并汇总
- **输出**（`moon run examples/telemetry`）：

```text
uplink batch 41 bytes: 0a 0a 73 65 6e 73 6f 72 2d 30 34 32 10 80 a8 a4 e0 ac 32 19 00 00 00 00 00 80 37 40 20 f4 1c 28 02 32 06 05 00 0a 18 0f 10
device=sensor-042 collected_at=1730000000000
temperature=23.5C battery=3700mV status=2(OK)
samples=6 min=-8 max=12 total=14
```

- **要点**：6 个采样值共用 1 个 tag 与 1 个长度前缀，没有逐元素 tag；`sint32` 先
  zigzag 再顺序拼接；`double` 以 8 字节小端承载。云端无需生成代码即可还原业务指标。

### 3.2 聊天消息解析与前向兼容（新版客户端 → 旧版服务端）

- **业务背景**：客户端升级后新增字段 9，旧服务端不认识该字段，但不能因此拒收整条消息。
- **字段约定**：1 `string sender`；2 `uint32 sent_at`；3 子消息
  `{ 1: string text, 2: bytes attachment }`；9 `string client_hint`（旧解析器未知）
- **调用**：`write_message` 构造嵌套正文、`write_bytes` 写入附件原始字节；
  解码端用 `read_submessage` 进入子窗口，用 `skip_tag` 跳过字段 9
- **输出**（`moon run examples/chat`）：

```text
chat message 57 bytes: 0a 05 61 6c 69 63 65 10 80 e9 f6 b8 06 1a 1c 0a 14 68 65 6c 6c 6f 20 66 72 6f 6d 20 4d 6f 6f 6e 50 72 6f 74 6f 12 04 89 50 4e 47 4a 0c 73 65 6e 74 2d 66 72 6f 6d 2d 76 32
sender=alice sent_at=1730000000
text=hello from MoonProto
attachment=4 bytes: 89 50 4e 47
skipped 1 unknown field(s), message still parsed
```

- **要点**：旧解析器只按已知字段号读取，未知字段按 wire type 原位跳过，其余字段照常
  还原；附件 `bytes` 原样返回，不经过 UTF-8 校验，因此可承载任意二进制。

### 3.3 协议调试与畸形输入定位（抓包回放 → 错误报告）

- **业务背景**：调试协议时既要还原合法报文，也要把畸形字节的失败位置写进报告。
- **输入**：先构造 `{ 1: uint32 150, 2: { 1: "leaf", 2: sint32 -7 } }`，得到 13 字节；
  再回放截断的 `08 80`。
- **调用**：`write_scalar_field` / `write_string` / `write_message`；解码端 `next_tag`、
  `read_scalar_field`、`read_submessage`
- **输出**（`moon run examples/basic`）：

```text
encoded 13 bytes: 08 96 01 12 08 0a 04 6c 65 61 66 10 0d
field 1 uint32 = 150
field 2 message depth = 1
  field 1 string = leaf
  field 2 sint32 = -7
malformed input rejected: truncated input at offset 1: needed 1 bytes, 0 available
```

- **要点**：子消息窗口被限制在声明长度内，父解码器同时越过整段 payload；截断输入
  不 panic、不返回半成品，而是抛出带绝对偏移与所需/可用字节数的
  `DecodeError::Truncated`，可直接写进调试报告。

## 四、核心功能范围

- **Varint（wire type 0）**：7 位一组、低位优先、续行位 0x80；最大 10 字节；
  接受非最短编码（与参考实现一致），区分"超过 10 字节"与"第 10 字节越界"两种错误。
- **Zigzag 32/64**：`sint32` / `sint64` 的编码与解码，`-1 ↦ 1`、`1 ↦ 2` 等映射逐位验证。
- **Fixed（wire type 1 / 5）**：`fixed32` / `sfixed32` / `float` 为 4 字节小端；
  `fixed64` / `sfixed64` / `double` 为 8 字节小端。
- **Tag 编解码（wire types 0–5）**：`field_number << 3 | wire_type`；
  字段号范围 `1..536870911`，编码时拒绝保留区 `19000..19999`，
  解码时拒绝 0 号/越界字段号、wire type 6/7 与超过 32 位的 tag。
- **全部 14 种标量**：`double`、`float`、`int32`、`int64`、`uint32`、`uint64`、
  `sint32`、`sint64`、`fixed32`、`fixed64`、`sfixed32`、`sfixed64`、`bool`、`enum`；
  读取前校验 tag 的 wire type 是否与标量匹配。
- **Length-delimited（wire type 2）**：`string` 按 UTF-8 校验并报 `InvalidUtf8(offset)`；
  `bytes` 原样返回；长度前缀与 payload 均受窗口边界检查。
- **Packed repeated fields**：同类型标量连续编码、无逐元素 tag；空数组不写字节；
  固定宽度类型校验 payload 长度必须为元素宽度的整数倍；混类型编码显式报错。
- **嵌套消息**：`write_message` 以长度界定方式嵌入子 `Encoder`；`read_submessage`
  返回独立窗口的子解码器，深度加一，超过 100 层抛 `RecursionLimitExceeded`。
- **Group 安全跳过**：解码侧完整支持 start-group / end-group 的递归匹配、字段号校验、
  未闭合检测与 100 层深度限制；编码侧不生成 group（proto3 不产出）。
- **未知字段前向兼容**：`skip_tag` 按 wire type 跳过 varint / fixed32 / fixed64 /
  length-delimited / group 任意 payload，调用方可忽略未知字段继续解析。
- **结构化错误**：14 个 `DecodeError` 变体 + 3 个 `EncodeError` 变体，均携带
  偏移、长度、字段号等诊断字段，并提供 `message() -> String`。
- **明确的功能边界（Scope）**：不提供 `.proto` 解析器、代码生成器、gRPC、JSON/Text
  映射、descriptor/反射、async/streaming、未知字段保留、多份同字段的 canonical merge、
  proto2 默认值与 map/oneof 的 schema 语义。map 与 oneof 在 wire 层没有独立编码，
  需要由调用方用 repeated message / 字段号约定自行表达。
- **公开文档**：[docs/API.md](./docs/API.md) 覆盖全部包、方法、wire type 对应表、
  错误表、边界限制与可复制的调用片段。

## 五、安装方式与快速开始

### 5.1 前置要求

| 依赖 | 版本要求 | 说明 |
| --- | --- | --- |
| MoonBit 工具链 | 已在 `moon 0.1.20261020` / `moonc v0.10.16` 上验证 | 项目以 MoonBit 为唯一实现语言；CI 每次安装官方最新工具链，并依次执行 `moon fmt --check`、`moon check --deny-warn`、`moon test --deny-warn` |
| 编译器后端 | 任一 `moon check --target` 支持的平台 | 纯逻辑实现，无需 gcc/Node.js，也不链接任何系统库 |

安装 MoonBit 工具链（Linux / macOS）：

```bash
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
export PATH="$HOME/.moon/bin:$PATH"
moon version --all
```

Windows 安装包见 <https://www.moonbitlang.com/download/>。

### 5.2 获取项目

```bash
git clone https://github.com/wuhaiting321/MoonProto.git
cd MoonProto
```

### 5.3 运行示例

三个独立示例分别对应第三节的三个业务场景：

```bash
moon run examples/telemetry   # 设备遥测批量上报
moon run examples/chat        # 聊天消息与前向兼容
moon run examples/basic       # 编解码往返与畸形输入
```

每个示例只读取内嵌字节，可离线重复运行，输出与第三节逐行一致。

### 5.4 构建与验证

```bash
moon fmt --check                    # 格式门禁
moon check --deny-warn              # 默认目标，零告警
moon check --target all --deny-warn # Native / Wasm / WasmGC / JS
moon test --deny-warn               # 109 个用例
```

仓库是**库**，`examples/*` 只是演示公开 API 的可执行包，不提供通用命令行工具。
测试数据全部内嵌在源码中，离线可跑。

### 5.5 作为依赖使用

项目尚未发布到 mooncakes.io（已列入后续计划）。当前获取源码后，在消费方
`moon.pkg` 中声明依赖路径，即可使用：

```moonbit
import {
  "wuhaiting321/moonproto/src/codec",
  "wuhaiting321/moonproto/src/types",
}
```

最小往返示例：

```moonbit
fn round_trip() -> Bytes raise {
  let encoder = @codec.Encoder::new()
  encoder.write_scalar_field(1, @types.ScalarValue::UInt32(150U))
  encoder.write_string(2, "hello")
  let bytes = encoder.finish()
  let decoder = @codec.Decoder::new(bytes)
  let tag = decoder.next_tag().unwrap()
  let _ = decoder.read_scalar_field(tag, @types.ScalarType::UInt32)
  bytes
}
```

## 六、技术亮点与实现说明

### 6.1 包结构与职责

| 包 | 职责 | 源码规模 |
| --- | --- | --- |
| `src/types` | 标量类型/值 ADT、`DecodeError`、`EncodeError` 与诊断文本 | 234 行 |
| `src/wire` | varint、zigzag、tag、带窗口边界的 `WireReader` | 614 行 |
| `src/codec` | `Encoder` / `Decoder`、标量、packed、嵌套消息与 group 跳过 | 448 行 |

依赖方向严格单向：`codec → wire → types`。底层包互不依赖，不存在环。上表合计
1296 行，另有 2235 行测试与 332 行示例，总计 3863 行，低于 5000 行的项目硬约束。

### 6.2 核心技术实现

1. **Varint 与 zigzag。** 编码端按 7 位一组写出，续行位置 0x80；解码端最多循环
   10 次，第 10 字节只允许 1 个有效位，分别报 `VarintTooLong` 与 `VarintOverflow`。
   非最短编码被接受，避免与参考实现产生"能解但不能编"的兼容性差异。负数 `int32`
   按符号扩展编成 10 字节 varint，`sint32` / `sint64` 走 zigzag。
2. **Tag 的双向校验。** 编码构造 `Tag` 时校验字段号范围与保留区；解码时额外限制
   tag varint 不超过 32 位，并拒绝 wire type 6/7。字段号与 wire type 通过私有字段 +
   getter 暴露，外部无法绕过构造校验。
3. **长度窗口与子读取器。** `WireReader` 持有 `[position, limit)` 窗口，所有读取先
   检查剩余字节；`read_length` 把声明的长度与窗口剩余量比较；`read_subreader`
   返回共享底层字节但独立 limit 的子读取器，父读取器同时越过 payload。因此嵌套消息
   与 packed 数组都"读不出自己的边界"。
4. **14 种标量的统一编解码。** `scalar_wire_type` 把标量类型映射到 wire type，
   `read_scalar_field` 在读取前校验 tag，`scalar_payload_len` 用于 packed 预计算。
   fixed 类型按小端逐字节组装；`bool` 以"非零即真"解码；`enum` 复用 int32 路径。
5. **Packed repeated。** 编码端先校验元素类型一致，再累加 payload 长度，最后一次性
   写 tag、长度与连续 payload；空数组直接返回。解码端把 payload 切成子窗口，
   定宽类型先检查长度是否整除，再循环读取，保证畸形 packed 不会影响外层对齐。
6. **嵌套消息与递归上限。** `write_message` 把子编码器的 `finish()` 结果作为
   length-delimited payload；`read_submessage` 校验 wire type 后进入子窗口，
   深度加一并保留绝对偏移，超过 `MAX_MESSAGE_DEPTH = 100` 直接拒绝。
7. **Group 跳过。** `skip_tag` 对 `StartGroup` 递归读取内部 tag，遇到字段号匹配的
   `EndGroup` 才返回；未闭合、字段号不匹配、孤立 end-group 分别报三种错误，
   深度上限 `MAX_GROUP_DEPTH = 100`。
8. **错误 ADT。** 解码错误按"截断、varint、tag、长度、group、递归、UTF-8、wire type、
   packed 宽度"分类，每个变体保留定位所需的数值；`message()` 生成可直接展示给用户的
   诊断文本，测试逐条断言文本内容。
9. **零 FFI 与多后端。** 全部代码只依赖 `moonbitlang/core`（`buffer` 与
   `encoding/utf8`），不出现 `extern "c"` / `extern "js"`；浮点仅用于
   `float`/`double` 的位重解释，不调用平台数学库。同一份源码在
   Native / Wasm / WasmGC / JS 上通过类型检查与测试。

### 6.3 数据流

```
编码
ScalarValue / String / Bytes / 子 Encoder
  ─► Tag（field_number << 3 | wire_type，varint）
  ─► payload（varint / fixed / length-delimited）
  ─► Buffer ─► Bytes
```

```
解码
Bytes ─► WireReader 窗口
  ─► next_tag ─► 按 wire type 分派
      ├─ Varint / Fixed32 / Fixed64 ─► read_scalar_field
      ├─ LengthDelimited ─► read_string / read_bytes
      │                     / read_submessage / read_packed_scalar_field
      └─ StartGroup / EndGroup ─► skip_tag（递归匹配）
```

### 6.4 验证与质量保障

- **CI 门禁**：GitHub Actions 在 Linux / macOS / Windows 上并行执行
  `moon fmt --check`、`moon check --deny-warn`、`moon test --deny-warn`。
- **测试规模**：109 个用例。`varint_test` 覆盖边界、zigzag 与两类溢出；
  `wire_type_test` / `reader_test` 覆盖 tag、窗口与 group；`encoder_test` /
  `decoder_test` 覆盖 string/bytes 与 UTF-8；`scalar_test` 覆盖 14 种标量的
  精确字节与往返；`packed_test` 覆盖全类型、空数组与畸形长度；`nested_test`
  覆盖三层递归、空子消息与 100 层限制；`robustness_test` 覆盖错误字段与消息文本。
- **穷举健壮性**：对全部 65,536 种两字节输入分别执行 tag 解析与完整 drain，
  断言只抛 `DecodeError`、绝不 panic；对一条含 string + packed + 子消息 + group 的
  复合消息，验证每一个前缀截断都只会成功或返回 `Truncated` / `LengthOutOfBounds`。
- **黑盒集成**：`test/` 作为独立包，只通过公开 API 调用 `codec` / `wire` / `types`，
  覆盖嵌套消息树往返、子窗口隔离、空子消息、group 跳过、递归上限、非法 schema
  与截断前缀，避免"用私有函数验证私有函数"。
- **示例实跑**：`examples/telemetry`、`examples/chat`、`examples/basic` 三个独立可执行包
  均在默认 WASI 目标上真实执行，输出见第三节。
- **本地多后端**：`moon check --target all --deny-warn` 覆盖四个后端，零告警。
- **已知验证缺口**：尚未接入官方 protobuf conformance 测试套件，也尚未引入
  外部解码器做交叉验证；这两项已列入后续计划，README 不以未完成的验证作为结论。

### 6.5 移植或参考说明

| 项目 | 内容 |
| --- | --- |
| 原项目名称 | 无，本项目为原创实现，不是移植项目 |
| 原项目链接 | 无 |
| 原项目许可证 | 不适用 |
| 本项目许可证 | Apache License 2.0 |

规范依据为 [Protocol Buffers Encoding](https://protobuf.dev/programming-guides/encoding/)
对 varint、tag、length-delimited、packed 与 group 的定义；测试中的经典向量
（如 `150 → 08 96 01`、`300 → AC 02`）与规范示例一致。实现代码与文档均为原创，
不包含来源不明的代码、私有代码、闭源代码或商业代码；仅依赖 Apache-2.0 授权的
MoonBit 官方标准库 `moonbitlang/core`。

仓库的包划分方式、`moon.pkg` 配置写法与测试命名风格参考了公开 MoonBit 项目
[moonbit-dwarfscope](https://github.com/wuhaiting321/moonbit-dwarfscope) 的
**工程组织方式**，未复制其任何业务逻辑或文档内容。

与相关公开工作的关系（截至 2026-10 检索）：

| 项目 | 定位 | 与本项目的关系 |
| --- | --- | --- |
| [moonbitlang/protobuf](https://mooncakes.io/docs/moonbitlang/protobuf) + [protoc-gen-mbt](https://github.com/moonbitlang/protoc-gen-mbt) | 官方 protobuf 运行时与代码生成器，服务 `.proto` 生成后的消息类型 | 互补：官方栈解决 schema → 代码；MoonProto 提供无生成步骤的动态 wire 层 |
| [123123213weqw/moon_proto](https://mooncakes.io/docs/123123213weqw/moon_proto) | 围绕官方栈的 schema 验证、兼容性检查与 AI 代码验证工具链 | 定位不同：本项目不解析 schema，只处理 wire bytes |
| [001-Elsa/moonpack](https://mooncakes.io/docs/001-Elsa/moonpack) | 借鉴 protobuf 思路、但不追求 protoc 兼容的 MoonBit 优先格式 | 定位不同：MoonProto 遵循 protobuf v3 wire format，可与现有 protobuf 数据互通 |
| [prost](https://crates.io/crates/prost) | Rust 的 protobuf 实现，从 proto2/proto3 生成惯用 Rust 代码 | 同类问题的 Rust 方案；本项目是 MoonBit 原生、无代码生成 |
| [protobuf.js](https://www.npmjs.com/package/protobufjs) | 纯 JavaScript 实现，可直接使用 `.proto`，支持运行时反射与代码生成 | 同类问题的 JS 方案；本项目不依赖 JS 运行时，面向 WASI 与多后端 |

就当前检索到的公开包而言，未发现与本项目定位完全相同的 MoonBit 包：
上述 MoonBit 项目以 schema 解析、代码生成或 schema 验证为入口，而 MoonProto
明确只做 wire format 的动态编解码层。若存在遗漏，欢迎通过 Issue 指正。

**AI 工具使用说明。** 开发过程中使用 AI 编程助手辅助代码生成、测试补全与文档撰写。
技术路径、功能边界、验证方式与开源合规由作者负责；每个提交在推送前均通过
`moon check --deny-warn` 与 `moon test --deny-warn`，未经验证的代码不进入历史。

### 6.6 风险分析与应对方案

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| 调用方必须自行维护字段号与类型 | 传错类型时无法在编译期发现 | API 在读取前校验 wire type；文档给出 14 种标量映射表与完整示例；后续可加可选 descriptor 便利层 |
| 恶意长度或深度导致资源耗尽 | 解析器读越界或递归过深 | 所有读取受窗口 limit 约束；长度与剩余字节比较；消息/group 深度上限 100；65,536 种两字节输入穷举验证不 panic |
| 自测存在"自己验证自己"的偏差 | 错误实现可能被自己的测试放过 | 使用规范中的经典向量与逐字节断言；黑盒集成测试只走公开 API；后续接入官方 conformance 套件 |
| 性能尚未量化 | 无法承诺吞吐指标 | 不宣称未测得的性能；解码为单遍 O(n)，无 schema 解析开销；后续补充基准测试与 Buffer 复用 |
| 与官方 protobuf 栈定位重叠 | 生态重复建设 | 明确只做 wire 层，不碰 schema/代码生成；保持 Apache-2.0，可与官方栈组合使用 |
| 功能范围蔓延导致质量下降 | 行数与复杂度失控 | README 明确非目标；核心保持在 1296 行；新增能力必须附带测试与文档 |

## 七、后续计划

- [x] 工程骨架、包分层与模块配置
- [x] Varint / zigzag 编解码与边界测试
- [x] Wire type 0–5 的 tag 解析与序列化
- [x] Length-delimited `string` / `bytes` 与 UTF-8 校验
- [x] 全部 14 种标量类型
- [x] Packed repeated fields
- [x] 嵌套消息递归与 100 层深度限制
- [x] 错误 ADT、诊断文本与穷举健壮性测试
- [x] 黑盒集成测试与 3 个独立可运行示例
- [x] API 文档
- [ ] 接入 protobuf conformance 测试子集
- [ ] 增加随机 fuzz / property-based 往返测试
- [ ] 补充基准测试，评估 Buffer 复用与零拷贝切片
- [ ] 发布到 mooncakes.io，提供 `moon add` 安装路径
- [ ] 可选的 descriptor 便利层（与核心解耦，不影响零代码生成约束）

---

## 许可证

Copyright 2026 wuhaiting321.

本项目采用 [Apache License 2.0](./LICENSE) 分发。
