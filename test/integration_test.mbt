// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Read the next tag and assert its field number and wire type.
fn expect_tag(
  decoder : @codec.Decoder,
  field_number : Int32,
  wire_type : @wire.WireType,
) -> @wire.Tag raise {
  match decoder.next_tag() {
    Some(tag) => {
      assert_eq(tag.field_number(), field_number)
      assert_true(tag.wire_type() == wire_type)
      tag
    }
    None => panic()
  }
}

///|
/// Consume every field of a message without a schema, using only the public
/// API. Malformed input is expected to raise `DecodeError`; reaching the end of
/// the message is success.
fn drain(decoder : @codec.Decoder) -> Unit raise @types.DecodeError {
  while !decoder.is_empty() {
    let tag = match decoder.next_tag() {
      Some(tag) => tag
      None => panic()
    }
    match tag.wire_type() {
      @wire.WireType::Varint => {
        let _ = decoder.read_scalar(@types.ScalarType::UInt64)
      }
      @wire.WireType::Fixed32 => {
        let _ = decoder.read_scalar(@types.ScalarType::Fixed32)
      }
      @wire.WireType::Fixed64 => {
        let _ = decoder.read_scalar(@types.ScalarType::Fixed64)
      }
      @wire.WireType::LengthDelimited => {
        let _ = decoder.read_bytes()
      }
      @wire.WireType::StartGroup | @wire.WireType::EndGroup =>
        decoder.skip_tag(tag)
    }
  }
}

///|
/// Build a four-level message tree that exercises strings, every scalar wire
/// type family, packed repeated fields, raw bytes, and embedded messages.
///
/// root
///   1: int32 42
///   2: string "root"
///   3: message child
///        1: string "child"
///        2: message leaf
///             1: string "leaf"
///             2: sint32 -7
///             3: packed fixed64 [1, 2]
///        3: bool true
///   4: packed int32 [-1, 0, 300]
///   5: bytes DE AD
fn build_sample() -> Bytes raise @types.EncodeError {
  let leaf = @codec.Encoder::new()
  leaf.write_string(1, "leaf")
  leaf.write_scalar_field(2, @types.ScalarValue::SInt32(-7))
  leaf.write_packed_scalar_field(3, [
    @types.ScalarValue::Fixed64(1UL),
    @types.ScalarValue::Fixed64(2UL),
  ])
  let child = @codec.Encoder::new()
  child.write_string(1, "child")
  child.write_message(2, leaf)
  child.write_scalar_field(3, @types.ScalarValue::Bool(true))
  let root = @codec.Encoder::new()
  root.write_scalar_field(1, @types.ScalarValue::Int32(42))
  root.write_string(2, "root")
  root.write_message(3, child)
  root.write_packed_scalar_field(4, [
    @types.ScalarValue::Int32(-1),
    @types.ScalarValue::Int32(0),
    @types.ScalarValue::Int32(300),
  ])
  root.write_bytes(5, b"\xDE\xAD")
  root.finish()
}

///|
test "nested message tree round trips through the public API" {
  let root = @codec.Decoder::new(build_sample())
  let root_int_tag = expect_tag(root, 1, @wire.WireType::Varint)
  assert_true(
    root.read_scalar_field(root_int_tag, @types.ScalarType::Int32) ==
    @types.ScalarValue::Int32(42),
  )
  let _ = expect_tag(root, 2, @wire.WireType::LengthDelimited)
  assert_eq(root.read_string(), "root")
  let child_tag = expect_tag(root, 3, @wire.WireType::LengthDelimited)
  let child = root.read_submessage(child_tag)
  assert_eq(child.depth(), 1)
  let _ = expect_tag(child, 1, @wire.WireType::LengthDelimited)
  assert_eq(child.read_string(), "child")
  let leaf_tag = expect_tag(child, 2, @wire.WireType::LengthDelimited)
  let leaf = child.read_submessage(leaf_tag)
  assert_eq(leaf.depth(), 2)
  let _ = expect_tag(leaf, 1, @wire.WireType::LengthDelimited)
  assert_eq(leaf.read_string(), "leaf")
  let leaf_sint_tag = expect_tag(leaf, 2, @wire.WireType::Varint)
  assert_true(
    leaf.read_scalar_field(leaf_sint_tag, @types.ScalarType::SInt32) ==
    @types.ScalarValue::SInt32(-7),
  )
  let leaf_packed_tag = expect_tag(leaf, 3, @wire.WireType::LengthDelimited)
  let fixed = leaf.read_packed_scalar_field(
    leaf_packed_tag,
    @types.ScalarType::Fixed64,
  )
  assert_eq(fixed.length(), 2)
  assert_true(fixed[0] == @types.ScalarValue::Fixed64(1UL))
  assert_true(fixed[1] == @types.ScalarValue::Fixed64(2UL))
  assert_true(leaf.is_empty())
  let child_bool_tag = expect_tag(child, 3, @wire.WireType::Varint)
  assert_true(
    child.read_scalar_field(child_bool_tag, @types.ScalarType::Bool) ==
    @types.ScalarValue::Bool(true),
  )
  assert_true(child.is_empty())
  let root_packed_tag = expect_tag(root, 4, @wire.WireType::LengthDelimited)
  let ints = root.read_packed_scalar_field(
    root_packed_tag,
    @types.ScalarType::Int32,
  )
  assert_eq(ints.length(), 3)
  assert_true(ints[0] == @types.ScalarValue::Int32(-1))
  assert_true(ints[1] == @types.ScalarValue::Int32(0))
  assert_true(ints[2] == @types.ScalarValue::Int32(300))
  let _ = expect_tag(root, 5, @wire.WireType::LengthDelimited)
  assert_true(root.read_bytes() == b"\xDE\xAD")
  assert_true(root.is_empty())
  assert_eq(root.position(), build_sample().length())
}

///|
test "submessage windows isolate nested reads from sibling fields" {
  let decoder = @codec.Decoder::new(b"\x1A\x05\x0A\x03abc\x20\x07")
  let child_tag = expect_tag(decoder, 3, @wire.WireType::LengthDelimited)
  let child = decoder.read_submessage(child_tag)
  assert_eq(child.depth(), 1)
  assert_eq(child.remaining(), 5)
  let _ = expect_tag(child, 1, @wire.WireType::LengthDelimited)
  assert_eq(child.read_string(), "abc")
  assert_true(child.is_empty())
  match child.next_tag() {
    None => ()
    Some(_) => panic()
  }
  let sibling_tag = expect_tag(decoder, 4, @wire.WireType::Varint)
  assert_true(
    decoder.read_scalar_field(sibling_tag, @types.ScalarType::Int32) ==
    @types.ScalarValue::Int32(7),
  )
  assert_true(decoder.is_empty())
}

///|
test "empty submessages terminate without consuming the parent" {
  let decoder = @codec.Decoder::new(b"\x1A\x00\x08\x01")
  let child_tag = expect_tag(decoder, 3, @wire.WireType::LengthDelimited)
  let child = decoder.read_submessage(child_tag)
  assert_true(child.is_empty())
  assert_eq(child.depth(), 1)
  let sibling_tag = expect_tag(decoder, 1, @wire.WireType::Varint)
  assert_true(
    decoder.read_scalar_field(sibling_tag, @types.ScalarType::UInt64) ==
    @types.ScalarValue::UInt64(1UL),
  )
}

///|
test "malformed nested payloads raise structured errors" {
  let inner = @codec.Encoder::new()
  inner.write_string(1, "abc")
  let outer = @codec.Encoder::new()
  outer.write_message(2, inner)
  let message = outer.finish()
  let truncated = @codec.Decoder::new(message[:message.length() - 1].to_owned())
  let truncated_tag = expect_tag(truncated, 2, @wire.WireType::LengthDelimited)
  assert_true(
    try {
      let _ = truncated.read_submessage(truncated_tag)
      false
    } catch {
      @types.LengthOutOfBounds(_) => true
      _ => false
    },
  )
  let windowed = @codec.Decoder::new(b"\x1A\x02\x0A\x05")
  let windowed_tag = expect_tag(windowed, 3, @wire.WireType::LengthDelimited)
  let child = windowed.read_submessage(windowed_tag)
  let _ = expect_tag(child, 1, @wire.WireType::LengthDelimited)
  assert_true(
    try {
      let _ = child.read_bytes()
      false
    } catch {
      @types.LengthOutOfBounds(_) => true
      _ => false
    },
  )
  let utf8_decoder = @codec.Decoder::new(b"\x1A\x05\x0A\x01\xFF\x20\x07")
  let utf8_tag = expect_tag(utf8_decoder, 3, @wire.WireType::LengthDelimited)
  let utf8_child = utf8_decoder.read_submessage(utf8_tag)
  let _ = expect_tag(utf8_child, 1, @wire.WireType::LengthDelimited)
  assert_true(
    try {
      let _ = utf8_child.read_string()
      false
    } catch {
      @types.InvalidUtf8(offset~) => offset == 4
      _ => false
    },
  )
  let packed_decoder = @codec.Decoder::new(b"\x22\x03\x00\x00\x00")
  let packed_tag = expect_tag(
    packed_decoder,
    4,
    @wire.WireType::LengthDelimited,
  )
  assert_true(
    try {
      let _ = packed_decoder.read_packed_scalar_field(
        packed_tag,
        @types.ScalarType::Fixed32,
      )
      false
    } catch {
      @types.InvalidPackedLength(length~, element_width~, ..) =>
        length == 3 && element_width == 4
      _ => false
    },
  )
  let wire_decoder = @codec.Decoder::new(b"\x08\x01")
  let wire_tag = expect_tag(wire_decoder, 1, @wire.WireType::Varint)
  assert_true(
    try {
      let _ = wire_decoder.read_submessage(wire_tag)
      false
    } catch {
      @types.UnexpectedWireType(expected~, actual~, ..) =>
        expected == 2 && actual == 0
      _ => false
    },
  )
  let zero_field = @codec.Decoder::new(b"\x00")
  assert_true(
    try {
      let _ = zero_field.next_tag()
      false
    } catch {
      @types.InvalidFieldNumber(field_number~, ..) => field_number == 0
      _ => false
    },
  )
}

///|
test "recursion limit stops hostile nesting" {
  let mut nested = @codec.Encoder::new()
  nested.write_scalar_field(1, @types.ScalarValue::Bool(true))
  for _ in 0..<(@codec.MAX_MESSAGE_DEPTH + 1) {
    let parent = @codec.Encoder::new()
    parent.write_message(1, nested)
    nested = parent
  }
  let mut decoder = @codec.Decoder::new(nested.finish())
  for level in 0..<@codec.MAX_MESSAGE_DEPTH {
    let tag = expect_tag(decoder, 1, @wire.WireType::LengthDelimited)
    decoder = decoder.read_submessage(tag)
    assert_eq(decoder.depth(), level + 1)
  }
  let tag = expect_tag(decoder, 1, @wire.WireType::LengthDelimited)
  assert_true(
    try {
      let _ = decoder.read_submessage(tag)
      false
    } catch {
      @types.RecursionLimitExceeded(limit~) => limit == @codec.MAX_MESSAGE_DEPTH
      _ => false
    },
  )
}

///|
test "group skipping stays inside the nested window" {
  let decoder = @codec.Decoder::new(b"\x1A\x04\x2B\x2C\x08\x07")
  let child_tag = expect_tag(decoder, 3, @wire.WireType::LengthDelimited)
  let child = decoder.read_submessage(child_tag)
  let group_tag = expect_tag(child, 5, @wire.WireType::StartGroup)
  child.skip_tag(group_tag)
  let value_tag = expect_tag(child, 1, @wire.WireType::Varint)
  assert_true(
    child.read_scalar_field(value_tag, @types.ScalarType::UInt64) ==
    @types.ScalarValue::UInt64(7UL),
  )
  assert_true(child.is_empty())
  assert_true(decoder.is_empty())
}

///|
test "every prefix of a valid nested message stays inside DecodeError" {
  let message = build_sample()
  for cut in 0..<=message.length() {
    let prefix = message[:cut].to_owned()
    let ok = try {
      drain(@codec.Decoder::new(prefix))
      true
    } catch {
      @types.Truncated(_) | @types.LengthOutOfBounds(_) => true
      _ => false
    }
    assert_true(ok)
  }
}

///|
test "encoder rejects invalid schemas through the public API" {
  let encoder = @codec.Encoder::new()
  assert_true(
    try {
      encoder.write_string(0, "zero")
      false
    } catch {
      @types.FieldNumberOutOfRange(field_number~) => field_number == 0
      _ => false
    },
  )
  assert_true(
    try {
      encoder.write_scalar_field(19000, @types.ScalarValue::Bool(true))
      false
    } catch {
      @types.ReservedFieldNumber(field_number~) => field_number == 19000
      _ => false
    },
  )
  assert_true(
    try {
      encoder.write_packed_scalar_field(1, [
        @types.ScalarValue::SInt32(1),
        @types.ScalarValue::UInt32(2U),
      ])
      false
    } catch {
      @types.PackedTypeMismatch(expected~, actual~) =>
        expected == "sint32" && actual == "uint32"
      _ => false
    },
  )
  assert_true(encoder.is_empty())
}
