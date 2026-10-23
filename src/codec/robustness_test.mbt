// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Consume every field of a message without knowing its schema.
///
/// The wire type determines which reader is used. Malformed input is expected
/// to raise `DecodeError`; reaching the end of the message is success.
fn drain(decoder : Decoder) -> Unit raise @types.DecodeError {
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
test "tag parser handles arbitrary two-byte inputs" {
  for first in 0..<256 {
    for second in 0..<256 {
      let bytes = Bytes::from_array([first.to_byte(), second.to_byte()])
      try {
        let _ = @wire.read_tag(bytes, 0)
      } catch {
        _ => ()
      }
    }
  }
}

///|
test "decoder consumes arbitrary two-byte messages without panicking" {
  for first in 0..<256 {
    for second in 0..<256 {
      let bytes = Bytes::from_array([first.to_byte(), second.to_byte()])
      drain(Decoder::new(bytes)) catch {
        _ => ()
      }
    }
  }
}

///|
test "every prefix of a nested message either decodes or raises" {
  let inner = Encoder::new()
  inner.write_string(1, "prefix")
  inner.write_packed_scalar_field(2, [
    @types.ScalarValue::SInt32(-1),
    @types.ScalarValue::SInt32(2),
  ])
  let outer = Encoder::new()
  outer.write_message(3, inner)
  outer.write_bytes(4, b"\xFF\xFE")
  outer.write_scalar_field(5, @types.ScalarValue::Bool(false))
  let message = outer.finish()
  for cut in 0..<=message.length() {
    let truncated = message[:cut].to_owned()
    drain(Decoder::new(truncated)) catch {
      _ => ()
    }
  }
}

///|
test "structured decode errors carry offsets and sizes" {
  assert_true(
    try {
      let _ = @wire.read_uvarint(b"\x80", 0)
      false
    } catch {
      @types.Truncated(offset~, needed~, available~) =>
        offset == 0 && needed == 1 && available == 0
      _ => false
    },
  )
  let length_decoder = Decoder::new(b"\x0A\x05abc")
  let _ = length_decoder.next_tag()
  assert_true(
    try {
      let _ = length_decoder.read_bytes()
      false
    } catch {
      @types.LengthOutOfBounds(offset~, length~, remaining~) =>
        offset == 1 && length == 5UL && remaining == 3
      _ => false
    },
  )
  assert_true(
    try {
      let _ = @wire.read_tag(b"\x00", 0)
      false
    } catch {
      @types.InvalidFieldNumber(field_number~, ..) => field_number == 0
      _ => false
    },
  )
  assert_true(
    try {
      let _ = @wire.read_tag(b"\x0E", 0)
      false
    } catch {
      @types.UnknownWireType(value~, ..) => value == 6
      _ => false
    },
  )
  assert_true(
    try {
      let _ = @wire.read_tag(b"\x80\x80\x80\x80\x10", 0)
      false
    } catch {
      @types.TagValueOutOfRange(value~, ..) => value == 0x100000000UL
      _ => false
    },
  )
  assert_true(
    try {
      let _ = @wire.read_uvarint(b"\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x02", 0)
      false
    } catch {
      @types.VarintOverflow(offset~) => offset == 0
      _ => false
    },
  )
  assert_true(
    try {
      let _ = @wire.read_uvarint(b"\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80", 0)
      false
    } catch {
      @types.VarintTooLong(offset~) => offset == 0
      _ => false
    },
  )
}

///|
test "group and UTF-8 errors expose their Context" {
  let reader = @wire.WireReader::new(b"\x14")
  assert_true(
    try {
      reader.skip_tag(@wire.Tag::new(1, @wire.WireType::StartGroup))
      false
    } catch {
      @types.MismatchedEndGroup(offset~, expected~, actual~) =>
        offset == 1 && expected == 1 && actual == 2
      _ => false
    },
  )
  let decoder = Decoder::new(b"\x0A\x01\xFF")
  match decoder.next_tag() {
    Some(_) =>
      assert_true(
        try {
          let _ = decoder.read_string()
          false
        } catch {
          @types.InvalidUtf8(offset~) => offset == 2
          _ => false
        },
      )
    None => assert_true(false)
  }
}

///|
test "decode error messages are actionable" {
  assert_eq(
    @types.Truncated(offset=3, needed=2, available=1).message(),
    "truncated input at offset 3: needed 2 bytes, 1 available",
  )
  assert_eq(
    @types.VarintTooLong(offset=4).message(),
    "varint at offset 4 exceeds 10 bytes",
  )
  assert_eq(
    @types.UnknownWireType(offset=0, value=6).message(),
    "unknown wire type 6",
  )
  assert_eq(
    @types.LengthOutOfBounds(offset=1, length=5UL, remaining=3).message(),
    "length 5 at offset 1 exceeds 3 remaining bytes",
  )
  assert_eq(
    @types.MismatchedEndGroup(offset=1, expected=1, actual=2).message(),
    "end-group field 2 does not match start-group field 1 at offset 1",
  )
  assert_eq(
    @types.UnexpectedWireType(offset=1, expected=2, actual=0).message(),
    "unexpected wire type 0, expected 2",
  )
  assert_eq(
    @types.InvalidPackedLength(offset=1, length=3, element_width=4).message(),
    "packed length 3 is not a multiple of 4",
  )
  assert_eq(
    @types.RecursionLimitExceeded(limit=100).message(),
    "recursion limit 100 exceeded",
  )
  assert_eq(@types.InvalidUtf8(offset=2).message(), "invalid UTF-8 at offset 2")
}

///|
test "encode error messages are actionable" {
  assert_eq(
    @types.FieldNumberOutOfRange(field_number=0).message(),
    "field number 0 is outside 1..536870911",
  )
  assert_eq(
    @types.ReservedFieldNumber(field_number=19000).message(),
    "field number 19000 is reserved",
  )
  assert_eq(
    @types.PackedTypeMismatch(expected="uint32", actual="int32").message(),
    "packed field mixes int32 with uint32",
  )
}
