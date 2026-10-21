// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
test "scalar payload lengths match their wire encodings" {
  assert_eq(scalar_payload_len(@types.ScalarValue::Bool(true)), 1)
  assert_eq(scalar_payload_len(@types.ScalarValue::Float(1.0)), 4)
  assert_eq(scalar_payload_len(@types.ScalarValue::Fixed32(1U)), 4)
  assert_eq(scalar_payload_len(@types.ScalarValue::SFixed32(-1)), 4)
  assert_eq(scalar_payload_len(@types.ScalarValue::Double(1.5)), 8)
  assert_eq(scalar_payload_len(@types.ScalarValue::Fixed64(1UL)), 8)
  assert_eq(scalar_payload_len(@types.ScalarValue::SFixed64(-1L)), 8)
  assert_eq(scalar_payload_len(@types.ScalarValue::UInt32(0U)), 1)
  assert_eq(scalar_payload_len(@types.ScalarValue::UInt32(128U)), 2)
  assert_eq(scalar_payload_len(@types.ScalarValue::Int32(-1)), 10)
  assert_eq(scalar_payload_len(@types.ScalarValue::SInt32(-1)), 1)
  assert_eq(scalar_payload_len(@types.ScalarValue::SInt64(-1L)), 1)
  assert_eq(scalar_payload_len(@types.ScalarValue::Enum(-1)), 10)
}

///|
test "scalar fields match protobuf reference encodings" {
  let encoder = Encoder::new()
  encoder.write_scalar_field(1, @types.ScalarValue::Double(1.5))
  encoder.write_scalar_field(2, @types.ScalarValue::Float(1.0))
  encoder.write_scalar_field(3, @types.ScalarValue::Int32(-1))
  encoder.write_scalar_field(4, @types.ScalarValue::Int64(-2L))
  assert_eq(
    encoder.finish(),
    b"\x09\x00\x00\x00\x00\x00\x00\xF8\x3F\x15\x00\x00\x80\x3F\x18\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x01\x20\xFE\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x01",
  )
}

///|
test "scalar fields cover every protobuf basic type" {
  let encoder = Encoder::new()
  encoder.write_scalar_field(5, @types.ScalarValue::UInt32(300U))
  encoder.write_scalar_field(
    6,
    @types.ScalarValue::UInt64(0x8000000000000000UL),
  )
  encoder.write_scalar_field(7, @types.ScalarValue::SInt32(-1))
  encoder.write_scalar_field(8, @types.ScalarValue::SInt64(-2L))
  encoder.write_scalar_field(9, @types.ScalarValue::Fixed32(0x12345678U))
  encoder.write_scalar_field(
    10,
    @types.ScalarValue::Fixed64(0x0123456789ABCDEFUL),
  )
  encoder.write_scalar_field(11, @types.ScalarValue::SFixed32(-1))
  encoder.write_scalar_field(12, @types.ScalarValue::SFixed64(-1L))
  encoder.write_scalar_field(13, @types.ScalarValue::Bool(true))
  encoder.write_scalar_field(14, @types.ScalarValue::Enum(-1))
  assert_eq(
    encoder.finish(),
    b"\x28\xAC\x02\x30\x80\x80\x80\x80\x80\x80\x80\x80\x80\x01\x38\x01\x40\x03\x4D\x78\x56\x34\x12\x51\xEF\xCD\xAB\x89\x67\x45\x23\x01\x5D\xFF\xFF\xFF\xFF\x61\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x68\x01\x70\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x01",
  )
}

///|
test "scalar values round-trip through the decoder" {
  let cases : Array[(@types.ScalarType, @types.ScalarValue)] = [
    (@types.ScalarType::Double, @types.ScalarValue::Double(-3.25)),
    (@types.ScalarType::Float, @types.ScalarValue::Float(0.5)),
    (@types.ScalarType::Int32, @types.ScalarValue::Int32(-2147483648)),
    (@types.ScalarType::Int64, @types.ScalarValue::Int64(-9223372036854775807L)),
    (@types.ScalarType::UInt32, @types.ScalarValue::UInt32(4294967295U)),
    (
      @types.ScalarType::UInt64,
      @types.ScalarValue::UInt64(0xFFFFFFFFFFFFFFFFUL),
    ),
    (@types.ScalarType::SInt32, @types.ScalarValue::SInt32(-2147483648)),
    (
      @types.ScalarType::SInt64,
      @types.ScalarValue::SInt64(-9223372036854775807L),
    ),
    (@types.ScalarType::Fixed32, @types.ScalarValue::Fixed32(0xDEADBEEFU)),
    (
      @types.ScalarType::Fixed64,
      @types.ScalarValue::Fixed64(0xDEADBEEFCAFEBABEUL),
    ),
    (@types.ScalarType::SFixed32, @types.ScalarValue::SFixed32(-123456789)),
    (
      @types.ScalarType::SFixed64,
      @types.ScalarValue::SFixed64(-123456789012345L),
    ),
    (@types.ScalarType::Bool, @types.ScalarValue::Bool(true)),
    (@types.ScalarType::Enum, @types.ScalarValue::Enum(-7)),
  ]
  for case in cases {
    let encoder = Encoder::new()
    encoder.write_scalar_field(1, case.1)
    let decoder = Decoder::new(encoder.finish())
    match decoder.next_tag() {
      Some(tag) => assert_eq(decoder.read_scalar_field(tag, case.0), case.1)
      None => assert_true(false)
    }
    assert_true(decoder.is_empty())
  }
}

///|
test "bool decoding accepts any non-zero varint as true" {
  let decoder = Decoder::new(b"\x08\x02")
  match decoder.next_tag() {
    Some(tag) =>
      assert_eq(
        decoder.read_scalar_field(tag, @types.ScalarType::Bool),
        @types.ScalarValue::Bool(true),
      )
    None => assert_true(false)
  }
}

///|
test "read_scalar can be used after consuming a tag" {
  let decoder = Decoder::new(b"\x08\xAC\x02")
  match decoder.next_tag() {
    Some(_) =>
      assert_eq(
        decoder.read_scalar(@types.ScalarType::UInt32),
        @types.ScalarValue::UInt32(300U),
      )
    None => assert_true(false)
  }
}

///|
test "read_scalar_field rejects mismatched wire types" {
  let varint_decoder = Decoder::new(b"\x08\x01")
  match varint_decoder.next_tag() {
    Some(tag) =>
      assert_true(
        try {
          let _ = varint_decoder.read_scalar_field(
            tag,
            @types.ScalarType::Fixed32,
          )
          false
        } catch {
          @types.UnexpectedWireType(expected~, actual~) =>
            expected == 5 && actual == 0
          _ => false
        },
      )
    None => assert_true(false)
  }
  let string_decoder = Decoder::new(b"\x0A\x01a")
  match string_decoder.next_tag() {
    Some(tag) =>
      assert_true(
        try {
          let _ = string_decoder.read_scalar_field(
            tag,
            @types.ScalarType::UInt32,
          )
          false
        } catch {
          @types.UnexpectedWireType(expected~, actual~) =>
            expected == 0 && actual == 2
          _ => false
        },
      )
    None => assert_true(false)
  }
}

///|
test "scalar encoders validate field numbers" {
  let encoder = Encoder::new()
  assert_true(
    try {
      encoder.write_scalar_field(0, @types.ScalarValue::UInt32(1U))
      false
    } catch {
      @types.FieldNumberOutOfRange(_) => true
      _ => false
    },
  )
  assert_true(
    try {
      encoder.write_scalar_field(19000, @types.ScalarValue::UInt32(1U))
      false
    } catch {
      @types.ReservedFieldNumber(_) => true
      _ => false
    },
  )
  assert_eq(encoder.finish(), b"")
}

///|
test "scalar decoders fail cleanly on truncated payloads" {
  let fixed = Decoder::new(b"\x0D\x01")
  match fixed.next_tag() {
    Some(tag) =>
      assert_true(
        try {
          let _ = fixed.read_scalar_field(tag, @types.ScalarType::Fixed32)
          false
        } catch {
          @types.Truncated(..) => true
          _ => false
        },
      )
    None => assert_true(false)
  }
  let varint = Decoder::new(b"\x08")
  match varint.next_tag() {
    Some(tag) =>
      assert_true(
        try {
          let _ = varint.read_scalar_field(tag, @types.ScalarType::UInt64)
          false
        } catch {
          @types.Truncated(..) => true
          _ => false
        },
      )
    None => assert_true(false)
  }
}
