# MoonProto API 文档

MoonProto 是纯 MoonBit 实现的 Protocol Buffers v3 **Wire Format** 编解码器。它不依赖
`.proto` 解析器或代码生成器，直接面向 wire bytes 提供增量式编码与解码原语，可在
WASM/WASI 沙箱中运行，零 FFI。

- 版本：0.1.0
- 许可证：Apache-2.0
- 仓库：https://github.com/wuhaiting321/MoonProto
- 可运行示例：[examples/basic/main.mbt](../examples/basic/main.mbt)

## 包结构

| 包 | 导入路径 | 职责 |
|---|---|---|
| `types` | `wuhaiting321/moonproto/src/types` | 标量类型/值 ADT、`DecodeError`、`EncodeError` |
| `wire` | `wuhaiting321/moonproto/src/wire` | varint、zigzag、tag、带边界检查的 `WireReader` |
| `codec` | `wuhaiting321/moonproto/src/codec` | `Encoder`、`Decoder`、标量/packed/嵌套消息编解码 |

依赖方向严格单向：`codec` → `wire` → `types`。

## 快速开始

```moonbit
import {
  "wuhaiting321/moonproto/src/codec",
  "wuhaiting321/moonproto/src/types",
}
```

编码一个包含 `uint32` 字段与嵌套消息的消息：

```moonbit
let leaf = @codec.Encoder::new()
leaf.write_string(1, "leaf")
leaf.write_scalar_field(2, @types.ScalarValue::SInt32(-7))

let root = @codec.Encoder::new()
root.write_scalar_field(1, @types.ScalarValue::UInt32(150U))
root.write_message(2, leaf)

let bytes = root.finish()
```

解码：

```moonbit
let decoder = @codec.Decoder::new(bytes)
while !decoder.is_empty() {
  let tag = match decoder.next_tag() {
    Some(tag) => tag
    None => break
  }
  match tag.field_number() {
    1 => {
      let _ = decoder.read_scalar_field(tag, @types.ScalarType::UInt32)
    }
    2 => {
      let child = decoder.read_submessage(tag)
      // 子解码器的窗口被限制在声明长度内，父解码器已越过该 payload。
      let _ = child.read_string()
    }
    _ => decoder.skip_tag(tag)
  }
}
```

## Encoder API

所有写方法按调用顺序追加字段；字段号与值类型由调用方显式给出，因此同一套 API
既能服务手写代码，也能服务未来的生成代码。

| 方法 | 说明 |
|---|---|
| `Encoder::new() -> Encoder` | 创建空编码器 |
| `Encoder::size() -> Int` | 已写入字节数 |
| `Encoder::is_empty() -> Bool` | 是否尚未写入任何字段 |
| `Encoder::finish() -> Bytes` | 返回当前字节的**副本**，编码器仍可继续使用 |
| `write_scalar_field(field_number, value) raise EncodeError` | 写一个标量字段：tag + 标量 payload |
| `write_string(field_number, value) raise EncodeError` | 写 UTF-8 `string` 字段 |
| `write_bytes(field_number, value) raise EncodeError` | 原样写 `bytes` 字段 |
| `write_length_delimited(field_number, payload) raise EncodeError` | 写 tag + varint 长度 + 原始 payload |
| `write_packed_scalar_field(field_number, values) raise EncodeError` | 写 packed repeated 标量数组 |
| `write_message(field_number, message) raise EncodeError` | 把另一个 `Encoder` 的内容作为嵌套消息写入 |

行为约定：

- 空数组的 packed 字段**不写任何字节**，与 proto3 省略空 repeated 字段一致。
- `write_packed_scalar_field` 要求所有元素类型一致，混类型抛 `PackedTypeMismatch`。
- `string` / `bytes` 不属于标量，不能 packed。
- 字段号必须是 `1..536870911`，且不能落在保留区 `19000..19999`。
- 负数 `int32`/`int64` 会符号扩展为 10 字节 varint；`sint32`/`sint64` 使用 zigzag。

## Decoder API

解码器是增量式的：`next_tag` 返回下一个 tag 并把游标停在 payload 起始处，调用方选择
对应的读取方法或 `skip_tag`。

| 方法 | 说明 |
|---|---|
| `Decoder::new(bytes) -> Decoder` | 覆盖完整字节序列 |
| `Decoder::new_limited(bytes, start, end) raise DecodeError` | 只在 `[start, end)` 窗口内解码 |
| `position() -> Int` | 当前绝对读取偏移 |
| `remaining() -> Int` | 当前窗口剩余字节数 |
| `is_empty() -> Bool` | 当前窗口是否已消费完 |
| `depth() -> Int` | 嵌套深度，顶层为 0 |
| `next_tag() -> Tag? raise DecodeError` | 读取下一个 tag；窗口耗尽返回 `None` |
| `read_scalar(scalar_type) raise DecodeError` | 按指定类型读取标量 payload（tag 已消费） |
| `read_scalar_field(tag, scalar_type) raise DecodeError` | 先校验 tag 的 wire type，再读取标量 |
| `read_string() raise DecodeError` | 读取长度界定字段并校验 UTF-8 |
| `read_bytes() raise DecodeError` | 读取长度界定字段的原始字节 |
| `read_packed_scalar_field(tag, scalar_type) raise DecodeError` | 在子窗口内解析 packed 数组 |
| `read_submessage(tag) raise DecodeError` | 返回限定在声明长度内的子解码器，`depth + 1` |
| `skip_tag(tag) raise DecodeError` | 跳过任意 wire type 的 payload，支持 group |

安全边界：

- 所有读取都会先检查窗口，绝不会越过声明长度读到相邻字段。
- 子消息深度超过 `MAX_MESSAGE_DEPTH = 100` 抛 `RecursionLimitExceeded`。
- group 跳过深度超过 `MAX_GROUP_DEPTH = 100` 抛 `RecursionLimitExceeded`。
- 读取 `string` 时非法 UTF-8 抛 `InvalidUtf8(offset)`，offset 为 payload 起始位置。

## 标量类型

| `ScalarType` | wire type | MoonBit 值类型（`ScalarValue`） | 编码 |
|---|---|---|---|
| `Double` | `Fixed64` | `Double` | little-endian IEEE-754 |
| `Float` | `Fixed32` | `Float` | little-endian IEEE-754 |
| `Int32` | `Varint` | `Int` | 负数符号扩展为 10 字节 |
| `Int64` | `Varint` | `Int64` | 负数符号扩展为 10 字节 |
| `UInt32` | `Varint` | `UInt` | 无符号 varint |
| `UInt64` | `Varint` | `UInt64` | 无符号 varint |
| `SInt32` | `Varint` | `Int` | zigzag32 |
| `SInt64` | `Varint` | `Int64` | zigzag64 |
| `Fixed32` | `Fixed32` | `UInt` | 4 字节 little-endian |
| `Fixed64` | `Fixed64` | `UInt64` | 8 字节 little-endian |
| `SFixed32` | `Fixed32` | `Int` | 4 字节 little-endian |
| `SFixed64` | `Fixed64` | `Int64` | 8 字节 little-endian |
| `Bool` | `Varint` | `Bool` | 任意非零 varint 解码为 `true` |
| `Enum` | `Varint` | `Int` | 与 int32 相同 |

辅助方法：

- `scalar_wire_type(ScalarType) -> WireType`
- `scalar_payload_len(ScalarValue) -> Int`（不含 tag 与长度前缀）
- `ScalarValue::scalar_type() -> ScalarType`
- `ScalarType::name() -> String`（如 `"sint32"`）

## Wire 原语（`@wire`）

### Varint

| 函数 | 说明 |
|---|---|
| `MAX_VARINT_BYTES : Int = 10` | 64 位 varint 的最大字节数 |
| `uvarint_len(value: UInt64) -> Int` | 编码所需字节数 |
| `write_uvarint(buffer, value)` | 追加到 `@buffer.Buffer` |
| `encode_uvarint(value) -> Bytes` | 返回独立字节数组 |
| `read_uvarint(bytes, offset) -> (UInt64, Int)` | 返回值和下一偏移；超 10 字节抛 `VarintTooLong`，第 10 字节越界抛 `VarintOverflow` |

非最短编码（如 `0x80 0x00` 表示 0）会被接受，这与 protobuf 实现的实际行为一致。

### Zigzag

| 函数 | 说明 |
|---|---|
| `zigzag_encode32(Int) -> UInt` | `(n << 1) ^ (n >> 31)` |
| `zigzag_decode32(UInt) -> Int` | 逆变换 |
| `zigzag_encode64(Int64) -> UInt64` | `(n << 1) ^ (n >> 63)` |
| `zigzag_decode64(UInt64) -> Int64` | 逆变换 |

类型转换辅助：`int32_to_u64`、`int64_to_u64`、`uint32_to_u64`、`sint32_to_u64`、
`sint64_to_u64`、`u64_to_int32`、`u64_to_int64`、`u64_to_uint32`、`u64_to_sint32`、
`u64_to_sint64`。

### Tag

| API | 说明 |
|---|---|
| `Tag::new(field_number, wire_type) raise EncodeError` | 构造并校验字段号 |
| `tag.field_number() -> Int` | 字段号 getter |
| `tag.wire_type() -> WireType` | wire type getter |
| `tag.encode() -> Bytes` | 编码为 `field_number << 3 \| wire_type` 的 varint |
| `tag.encoded_len() -> Int` | 编码后字节数 |
| `write_tag(buffer, tag)` | 追加 tag |
| `read_tag(bytes, offset) -> (Tag, Int) raise DecodeError` | 解析 tag；字段号 0/越界抛 `InvalidFieldNumber`，wire type 6/7 抛 `UnknownWireType`，超过 32 位抛 `TagValueOutOfRange` |

`WireType` 提供 `to_int()`、`from_int(value) raise DecodeError`、`is_packable()`。
常量：`MIN_FIELD_NUMBER = 1`、`MAX_FIELD_NUMBER = 536870911`、
`FIRST_RESERVED_FIELD_NUMBER = 19000`、`LAST_RESERVED_FIELD_NUMBER = 19999`。

### WireReader

`WireReader` 是 `Decoder` 的底层游标，拥有窗口 `[position, limit)`。

| API | 说明 |
|---|---|
| `new(bytes)` / `new_limited(bytes, start, end) raise DecodeError` | 创建读取器 |
| `position()` / `remaining()` / `is_empty()` | 游标状态 |
| `read_byte()` / `read_varint()` | 基础读取 |
| `read_fixed32()` / `read_fixed64()` | little-endian |
| `read_float()` / `read_double()` | IEEE-754 |
| `read_length() -> Int` | 读取长度前缀并校验，游标停在 payload 起始处 |
| `read_bytes(length)` | 读取指定长度的副本 |
| `read_subreader() -> WireReader` | 返回 payload 窗口，父读取器越过 payload |
| `next_tag() -> Tag` | 读取 tag |
| `skip(count)` / `skip_tag(tag, depth?=0)` | 跳过 payload，group 递归匹配 end-group |

## 错误处理

所有解码失败都抛出结构化 `DecodeError`，不会 panic。

### `DecodeError`

| 变体 | 触发条件 | 关键字段 |
|---|---|---|
| `Truncated` | 输入在读取完成前结束 | `offset`、`needed`、`available` |
| `VarintTooLong` | varint 超过 10 字节 | `offset` |
| `VarintOverflow` | 第 10 字节携带超出 64 位的位 | `offset` |
| `UnknownWireType` | wire type 为 6 或 7 | `value` |
| `InvalidFieldNumber` | 字段号为 0 或超过 536870911 | `field_number` |
| `TagValueOutOfRange` | tag varint 超过 32 位 | `value` |
| `LengthOutOfBounds` | 声明长度超过剩余字节 | `offset`、`length`、`remaining` |
| `UnexpectedEndGroup` | 没有对应 start-group 的 end-group | `offset` |
| `MismatchedEndGroup` | end-group 字段号与 start-group 不一致 | `offset`、`expected`、`actual` |
| `UnterminatedGroup` | 输入在 group 关闭前结束 | `offset` |
| `RecursionLimitExceeded` | 嵌套超过 100 层 | `limit` |
| `InvalidUtf8` | 字符串字段包含非法 UTF-8 | `offset` |
| `UnexpectedWireType` | tag 的 wire type 与期望不符 | `expected`、`actual` |
| `InvalidPackedLength` | 定宽 packed 长度不是元素宽度整数倍 | `length`、`element_width` |

每个变体都提供 `message() -> String`：

```moonbit
let decoder = @codec.Decoder::new(b"\x0A\x05abc")
let _ = decoder.next_tag()
try {
  let _ = decoder.read_bytes()
} catch {
  error => println(error.message())
  // length 5 at offset 1 exceeds 3 remaining bytes
}
```

### `EncodeError`

| 变体 | 触发条件 |
|---|---|
| `FieldNumberOutOfRange` | 字段号不在 `1..536870911` |
| `ReservedFieldNumber` | 字段号落在 `19000..19999` |
| `PackedTypeMismatch` | packed 数组混用不同标量类型 |

同样提供 `message() -> String`。

### 推荐解码循环

对未知字段使用 `skip_tag`，保证前向兼容：

```moonbit
fn decode_all(decoder : @codec.Decoder) -> Unit raise @types.DecodeError {
  while !decoder.is_empty() {
    let tag = match decoder.next_tag() {
      Some(tag) => tag
      None => break
    }
    match tag.field_number() {
      1 => {
        let _ = decoder.read_scalar_field(tag, @types.ScalarType::UInt64)
      }
      2 => {
        let _ = decoder.read_string()
      }
      _ => decoder.skip_tag(tag)
    }
  }
}
```

## 完整示例

可运行工程位于 [examples/basic](../examples/basic)。执行：

```bash
moon run examples/basic
```

实际输出：

```text
encoded 13 bytes: 08 96 01 12 08 0a 04 6c 65 61 66 10 0d
field 1 uint32 = 150
field 2 message depth = 1
  field 1 string = leaf
  field 2 sint32 = -7
malformed input rejected: truncated input at offset 1: needed 1 bytes, 0 available
```

该输出同时验证了：tag 编码、varint、length-delimited、嵌套子消息、zigzag，
以及截断输入的错误诊断。

## 验证

```bash
moon build --deny-warn
moon check --deny-warn
moon test
```

测试覆盖 varint 边界、wire type/tag、string/bytes、全部标量类型、packed、嵌套消息、
group 跳过，以及 65,536 种两字节输入的健壮性穷举。
