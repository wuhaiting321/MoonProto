// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
test "reader walks tags and varint payloads" {
  let reader = WireReader::new(b"\x08\x96\x01")
  let tag = reader.next_tag()
  assert_eq(tag.field_number(), 1)
  assert_eq(tag.wire_type(), WireType::Varint)
  assert_eq(reader.position(), 1)
  assert_eq(reader.read_varint(), 150UL)
  assert_true(reader.is_empty())
}

///|
test "reader reports remaining bytes within its window" {
  let reader = WireReader::new_limited(b"\x00\x08\x01\x00", 1, 3)
  assert_eq(reader.position(), 1)
  assert_eq(reader.remaining(), 2)
  let tag = reader.next_tag()
  assert_eq(tag.field_number(), 1)
  assert_eq(reader.read_varint(), 1UL)
  assert_eq(reader.remaining(), 0)
  assert_true(reader.is_empty())
}

///|
test "new_limited rejects invalid windows" {
  for window in [(-1, 2), (2, 1), (0, 10)] {
    assert_true(
      try {
        let _ = WireReader::new_limited(b"\x00\x01", window.0, window.1)
        false
      } catch {
        @types.Truncated(..) => true
        _ => false
      },
    )
  }
}

///|
test "reader decodes little-endian fixed32 and fixed64" {
  let fixed32 = WireReader::new(b"\x78\x56\x34\x12")
  assert_eq(fixed32.read_fixed32(), 0x12345678U)
  assert_true(fixed32.is_empty())
  let fixed64 = WireReader::new(b"\xEF\xCD\xAB\x89\x67\x45\x23\x01")
  assert_eq(fixed64.read_fixed64(), 0x0123456789ABCDEFUL)
  assert_true(fixed64.is_empty())
}

///|
test "reader decodes little-endian floats and doubles" {
  let float_reader = WireReader::new(b"\x00\x00\x80\x3F")
  assert_eq(float_reader.read_float(), (1.0 : Float))
  let double_reader = WireReader::new(b"\x00\x00\x00\x00\x00\x00\xF8\x3F")
  assert_eq(double_reader.read_double(), 1.5)
}

///|
test "fixed-width reads fail cleanly when truncated" {
  for bytes in [b"", b"\x00", b"\x00\x00\x00"] {
    assert_true(
      try {
        let _ = WireReader::new(bytes).read_fixed32()
        false
      } catch {
        @types.Truncated(..) => true
        _ => false
      },
    )
  }
  assert_true(
    try {
      let _ = WireReader::new(b"\x00\x00\x00\x00").read_fixed64()
      false
    } catch {
      @types.Truncated(..) => true
      _ => false
    },
  )
}

///|
test "read_length validates the payload against the window" {
  let reader = WireReader::new(b"\x03abc")
  assert_eq(reader.read_length(), 3)
  assert_eq(reader.position(), 1)
  assert_eq(reader.read_bytes(3), b"abc")
  assert_true(reader.is_empty())
  let empty = WireReader::new(b"\x00")
  assert_eq(empty.read_length(), 0)
  assert_true(empty.is_empty())
}

///|
test "read_length rejects lengths beyond the remaining input" {
  assert_true(
    try {
      let _ = WireReader::new(b"\x05abc").read_length()
      false
    } catch {
      @types.LengthOutOfBounds(length~, remaining~, ..) =>
        length == 5UL && remaining == 3
      _ => false
    },
  )
  assert_true(
    try {
      let _ = WireReader::new(b"\x80").read_length()
      false
    } catch {
      @types.Truncated(..) => true
      _ => false
    },
  )
}

///|
test "read_bytes copies exactly the requested window" {
  let reader = WireReader::new(b"abcXYZ")
  assert_eq(reader.read_bytes(3), b"abc")
  assert_eq(reader.position(), 3)
  assert_eq(reader.read_bytes(3), b"XYZ")
  assert_true(reader.is_empty())
  assert_true(
    try {
      let _ = WireReader::new(b"abc").read_bytes(4)
      false
    } catch {
      @types.LengthOutOfBounds(..) => true
      _ => false
    },
  )
  assert_true(
    try {
      let _ = WireReader::new(b"abc").read_bytes(-1)
      false
    } catch {
      @types.LengthOutOfBounds(..) => true
      _ => false
    },
  )
}

///|
test "subreaders isolate nested payloads from their parent" {
  let parent = WireReader::new(b"\x03abc\x02de")
  let child = parent.read_subreader()
  assert_eq(parent.position(), 4)
  assert_eq(parent.remaining(), 3)
  assert_eq(child.remaining(), 3)
  assert_eq(child.read_bytes(3), b"abc")
  assert_true(child.is_empty())
  assert_eq(parent.read_length(), 2)
  assert_eq(parent.read_bytes(2), b"de")
  assert_true(parent.is_empty())
}

///|
test "skip_tag consumes each scalar wire-type payload" {
  let varint = WireReader::new(b"\x96\x01")
  varint.skip_tag(Tag::new(1, WireType::Varint))
  assert_true(varint.is_empty())

  let fixed64 = WireReader::new(b"\x01\x02\x03\x04\x05\x06\x07\x08")
  fixed64.skip_tag(Tag::new(1, WireType::Fixed64))
  assert_true(fixed64.is_empty())

  let length_delimited = WireReader::new(b"\x03abc")
  length_delimited.skip_tag(Tag::new(1, WireType::LengthDelimited))
  assert_true(length_delimited.is_empty())

  let fixed32 = WireReader::new(b"\x01\x02\x03\x04")
  fixed32.skip_tag(Tag::new(1, WireType::Fixed32))
  assert_true(fixed32.is_empty())
}

///|
test "skip_tag walks nested groups to their matching end tag" {
  let bytes = b"\x0B\x13\x10\x01\x14\x0C"
  let reader = WireReader::new(bytes)
  let tag = reader.next_tag()
  assert_eq(tag.wire_type(), WireType::StartGroup)
  reader.skip_tag(tag)
  assert_true(reader.is_empty())
}

///|
test "skip_tag rejects standalone, mismatched, and unterminated groups" {
  let standalone = WireReader::new(b"")
  assert_true(
    try {
      standalone.skip_tag(Tag::new(1, WireType::EndGroup))
      false
    } catch {
      @types.UnexpectedEndGroup(_) => true
      _ => false
    },
  )

  let mismatched = WireReader::new(b"\x14")
  assert_true(
    try {
      mismatched.skip_tag(Tag::new(1, WireType::StartGroup))
      false
    } catch {
      @types.MismatchedEndGroup(expected~, actual~, ..) =>
        expected == 1 && actual == 2
      _ => false
    },
  )

  let unterminated = WireReader::new(b"\x10\x01")
  assert_true(
    try {
      unterminated.skip_tag(Tag::new(1, WireType::StartGroup))
      false
    } catch {
      @types.UnterminatedGroup(_) => true
      _ => false
    },
  )
}
