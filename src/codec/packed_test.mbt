// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Encode and decode one packed field for round-trip assertions.
fn packed_roundtrip(
  field_number : Int,
  scalar_type : @types.ScalarType,
  values : Array[@types.ScalarValue],
) -> Array[@types.ScalarValue] raise @types.DecodeError {
  let encoder = Encoder::new()
  encoder.write_packed_scalar_field(field_number, values) catch {
    _ => panic()
  }
  let decoder = Decoder::new(encoder.finish())
  let tag = match decoder.next_tag() {
    Some(tag) => tag
    None => panic()
  }
  decoder.read_packed_scalar_field(tag, scalar_type)
}

///|
test "packed sint32 uses back-to-back zigzag varints" {
  let encoder = Encoder::new()
  encoder.write_packed_scalar_field(1, [
    @types.ScalarValue::SInt32(-1),
    @types.ScalarValue::SInt32(1),
    @types.ScalarValue::SInt32(-2),
    @types.ScalarValue::SInt32(2),
  ])
  assert_eq(encoder.finish(), b"\x0A\x04\x01\x02\x03\x04")
}

///|
test "packed bool and fixed-width payloads use element encodings only" {
  let bools = Encoder::new()
  bools.write_packed_scalar_field(2, [
    @types.ScalarValue::Bool(true),
    @types.ScalarValue::Bool(false),
    @types.ScalarValue::Bool(true),
  ])
  assert_eq(bools.finish(), b"\x12\x03\x01\x00\x01")

  let fixed32 = Encoder::new()
  fixed32.write_packed_scalar_field(3, [
    @types.ScalarValue::Fixed32(1U),
    @types.ScalarValue::Fixed32(2U),
  ])
  assert_eq(fixed32.finish(), b"\x1A\x08\x01\x00\x00\x00\x02\x00\x00\x00")

  let float = Encoder::new()
  float.write_packed_scalar_field(4, [@types.ScalarValue::Float(1.0)])
  assert_eq(float.finish(), b"\x22\x04\x00\x00\x80\x3F")

  let double = Encoder::new()
  double.write_packed_scalar_field(5, [@types.ScalarValue::Double(1.5)])
  assert_eq(double.finish(), b"\x2A\x08\x00\x00\x00\x00\x00\x00\xF8\x3F")
}

///|
test "packed uint64 handles multiple length classes" {
  let encoder = Encoder::new()
  encoder.write_packed_scalar_field(6, [
    @types.ScalarValue::UInt64(0UL),
    @types.ScalarValue::UInt64(127UL),
    @types.ScalarValue::UInt64(128UL),
    @types.ScalarValue::UInt64(0xFFFFFFFFFFFFFFFFUL),
  ])
  assert_eq(
    encoder.finish(),
    b"\x32\x0E\x00\x7F\x80\x01\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x01",
  )
}

///|
test "packed negative int32 and enum use ten-byte elements" {
  let int32 = Encoder::new()
  int32.write_packed_scalar_field(7, [@types.ScalarValue::Int32(-1)])
  assert_eq(int32.finish(), b"\x3A\x0A\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x01")
  let enum_encoder = Encoder::new()
  enum_encoder.write_packed_scalar_field(8, [@types.ScalarValue::Enum(-1)])
  assert_eq(
    enum_encoder.finish(),
    b"\x42\x0A\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x01",
  )
}

///|
test "packed scalars round-trip for every numeric type" {
  let cases : Array[(@types.ScalarType, Array[@types.ScalarValue])] = [
    (
      @types.ScalarType::Int32,
      [
        @types.ScalarValue::Int32(0),
        @types.ScalarValue::Int32(-1),
        @types.ScalarValue::Int32(2147483647),
        @types.ScalarValue::Int32(-2147483648),
      ],
    ),
    (
      @types.ScalarType::UInt32,
      [@types.ScalarValue::UInt32(0U), @types.ScalarValue::UInt32(4294967295U)],
    ),
    (
      @types.ScalarType::SInt32,
      [
        @types.ScalarValue::SInt32(-2147483648),
        @types.ScalarValue::SInt32(2147483647),
      ],
    ),
    (
      @types.ScalarType::SInt64,
      [
        @types.ScalarValue::SInt64(-9223372036854775807L),
        @types.ScalarValue::SInt64(9223372036854775807L),
      ],
    ),
    (
      @types.ScalarType::Fixed32,
      [
        @types.ScalarValue::Fixed32(0U),
        @types.ScalarValue::Fixed32(0xFFFFFFFFU),
      ],
    ),
    (
      @types.ScalarType::SFixed32,
      [
        @types.ScalarValue::SFixed32(-1),
        @types.ScalarValue::SFixed32(2147483647),
      ],
    ),
    (
      @types.ScalarType::Fixed64,
      [
        @types.ScalarValue::Fixed64(0UL),
        @types.ScalarValue::Fixed64(0xFFFFFFFFFFFFFFFFUL),
      ],
    ),
    (
      @types.ScalarType::SFixed64,
      [
        @types.ScalarValue::SFixed64(-1L),
        @types.ScalarValue::SFixed64(9223372036854775807L),
      ],
    ),
    (
      @types.ScalarType::Float,
      [@types.ScalarValue::Float(0.0), @types.ScalarValue::Float(-1.5)],
    ),
    (
      @types.ScalarType::Double,
      [@types.ScalarValue::Double(0.0), @types.ScalarValue::Double(-1.5)],
    ),
    (
      @types.ScalarType::Bool,
      [@types.ScalarValue::Bool(false), @types.ScalarValue::Bool(true)],
    ),
    (
      @types.ScalarType::Enum,
      [
        @types.ScalarValue::Enum(0),
        @types.ScalarValue::Enum(-1),
        @types.ScalarValue::Enum(2147483647),
      ],
    ),
  ]
  for case in cases {
    assert_eq(packed_roundtrip(1, case.0, case.1), case.1)
  }
}

///|
test "packed int64 and uint64 round-trip boundary values" {
  let int64_values = [
    @types.ScalarValue::Int64(-9223372036854775807L),
    @types.ScalarValue::Int64(0L),
    @types.ScalarValue::Int64(9223372036854775807L),
  ]
  assert_eq(
    packed_roundtrip(2, @types.ScalarType::Int64, int64_values),
    int64_values,
  )
  let uint64_values = [
    @types.ScalarValue::UInt64(0UL),
    @types.ScalarValue::UInt64(0xFFFFFFFFFFFFFFFFUL),
  ]
  assert_eq(
    packed_roundtrip(3, @types.ScalarType::UInt64, uint64_values),
    uint64_values,
  )
}

///|
test "empty packed arrays write no bytes" {
  let encoder = Encoder::new()
  encoder.write_packed_scalar_field(1, [])
  assert_eq(encoder.finish(), b"")
  assert_true(encoder.is_empty())
}

///|
test "packed arrays reject mixed scalar types" {
  let encoder = Encoder::new()
  assert_true(
    try {
      encoder.write_packed_scalar_field(1, [
        @types.ScalarValue::UInt32(1U),
        @types.ScalarValue::Int32(2),
      ])
      false
    } catch {
      @types.PackedTypeMismatch(expected~, actual~) =>
        expected == "uint32" && actual == "int32"
      _ => false
    },
  )
  assert_eq(encoder.finish(), b"")
}

///|
test "packed encoders validate field numbers even for empty arrays" {
  let encoder = Encoder::new()
  assert_true(
    try {
      encoder.write_packed_scalar_field(19000, [])
      false
    } catch {
      @types.ReservedFieldNumber(_) => true
      _ => false
    },
  )
}

///|
test "decoder accepts an empty packed payload" {
  let decoder = Decoder::new(b"\x0A\x00")
  match decoder.next_tag() {
    Some(tag) =>
      assert_eq(
        decoder.read_packed_scalar_field(tag, @types.ScalarType::UInt32),
        [],
      )
    None => assert_true(false)
  }
  assert_true(decoder.is_empty())
}

///|
test "decoder rejects partial fixed-width packed elements" {
  let decoder = Decoder::new(b"\x0A\x03\x01\x02\x03")
  match decoder.next_tag() {
    Some(tag) =>
      assert_true(
        try {
          let _ = decoder.read_packed_scalar_field(
            tag,
            @types.ScalarType::Fixed32,
          )
          false
        } catch {
          @types.InvalidPackedLength(length~, element_width~) =>
            length == 3 && element_width == 4
          _ => false
        },
      )
    None => assert_true(false)
  }
}

///|
test "decoder rejects truncated packed varints" {
  let decoder = Decoder::new(b"\x0A\x01\x80")
  match decoder.next_tag() {
    Some(tag) =>
      assert_true(
        try {
          let _ = decoder.read_packed_scalar_field(
            tag,
            @types.ScalarType::UInt32,
          )
          false
        } catch {
          @types.Truncated(..) => true
          _ => false
        },
      )
    None => assert_true(false)
  }
}

///|
test "packed decoder validates the wire type" {
  let decoder = Decoder::new(b"\x08\x01")
  match decoder.next_tag() {
    Some(tag) =>
      assert_true(
        try {
          let _ = decoder.read_packed_scalar_field(
            tag,
            @types.ScalarType::UInt32,
          )
          false
        } catch {
          @types.UnexpectedWireType(expected~, actual~) =>
            expected == 2 && actual == 0
          _ => false
        },
      )
    None => assert_true(false)
  }
}

///|
test "packed fields keep the surrounding message aligned" {
  let encoder = Encoder::new()
  encoder.write_packed_scalar_field(1, [
    @types.ScalarValue::SInt32(1),
    @types.ScalarValue::SInt32(2),
  ])
  encoder.write_bytes(2, b"X")
  let decoder = Decoder::new(encoder.finish())
  match decoder.next_tag() {
    Some(tag) =>
      assert_eq(
        decoder.read_packed_scalar_field(tag, @types.ScalarType::SInt32),
        [@types.ScalarValue::SInt32(1), @types.ScalarValue::SInt32(2)],
      )
    None => assert_true(false)
  }
  match decoder.next_tag() {
    Some(_) => assert_eq(decoder.read_bytes(), b"X")
    None => assert_true(false)
  }
  assert_true(decoder.is_empty())
}

///|
test "packed payloads longer than 127 bytes use multi-byte lengths" {
  let values : Array[@types.ScalarValue] = []
  for _ in 0..<300 {
    values.push(@types.ScalarValue::UInt32(1U))
  }
  let encoder = Encoder::new()
  encoder.write_packed_scalar_field(1, values)
  let bytes = encoder.finish()
  assert_eq(bytes[0], b'\x0A')
  assert_eq(bytes[1], b'\xAC')
  assert_eq(bytes[2], b'\x02')
  assert_eq(bytes.length(), 303)
  assert_eq(packed_roundtrip(1, @types.ScalarType::UInt32, values), values)
}
