// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
test "decoder walks string and bytes fields" {
  let decoder = Decoder::new(b"\x0A\x05hello\x12\x02\x00\xFF")
  match decoder.next_tag() {
    Some(tag) => {
      assert_eq(tag.field_number(), 1)
      assert_eq(tag.wire_type(), @wire.WireType::LengthDelimited)
      assert_eq(decoder.read_string(), "hello")
    }
    None => assert_true(false)
  }
  match decoder.next_tag() {
    Some(tag) => {
      assert_eq(tag.field_number(), 2)
      assert_eq(decoder.read_bytes(), b"\x00\xFF")
    }
    None => assert_true(false)
  }
  assert_true(decoder.is_empty())
  assert_eq(decoder.next_tag(), None)
  assert_eq(decoder.position(), 11)
}

///|
test "decoder round-trips UTF-8 strings" {
  let encoder = Encoder::new()
  encoder.write_string(1, "你好, MoonBit 🚀")
  let decoder = Decoder::new(encoder.finish())
  match decoder.next_tag() {
    Some(_) => assert_eq(decoder.read_string(), "你好, MoonBit 🚀")
    None => assert_true(false)
  }
  assert_true(decoder.is_empty())
}

///|
test "decoder reads empty length-delimited payloads" {
  let decoder = Decoder::new(b"\x0A\x00\x12\x00")
  match decoder.next_tag() {
    Some(_) => assert_eq(decoder.read_string(), "")
    None => assert_true(false)
  }
  match decoder.next_tag() {
    Some(_) => assert_eq(decoder.read_bytes(), b"")
    None => assert_true(false)
  }
  assert_true(decoder.is_empty())
}

///|
test "read_string rejects malformed UTF-8" {
  let decoder = Decoder::new(b"\x0A\x02\xFF\xFE")
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
  assert_true(decoder.is_empty())
  let bytes_decoder = Decoder::new(b"\x12\x02\xFF\xFE")
  match bytes_decoder.next_tag() {
    Some(_) => assert_eq(bytes_decoder.read_bytes(), b"\xFF\xFE")
    None => assert_true(false)
  }
}

///|
test "decoder reports truncated length-delimited payloads" {
  for bytes in [b"\x0A", b"\x0A\x80", b"\x0A\x05abc"] {
    let decoder = Decoder::new(bytes)
    match decoder.next_tag() {
      Some(_) =>
        assert_true(
          try {
            let _ = decoder.read_string()
            false
          } catch {
            @types.Truncated(..) | @types.LengthOutOfBounds(..) => true
            _ => false
          },
        )
      None => assert_true(false)
    }
  }
}

///|
test "decoder skips length-delimited fields" {
  let decoder = Decoder::new(b"\x0A\x03abc\x12\x01X")
  match decoder.next_tag() {
    Some(tag) => decoder.skip_tag(tag)
    None => assert_true(false)
  }
  match decoder.next_tag() {
    Some(tag) => {
      assert_eq(tag.field_number(), 2)
      assert_eq(decoder.read_bytes(), b"X")
    }
    None => assert_true(false)
  }
  assert_true(decoder.is_empty())
}

///|
test "decoder respects a limited window" {
  let decoder = Decoder::new_limited(b"\xAA\x0A\x03abc\xBB", 1, 6)
  assert_eq(decoder.remaining(), 5)
  match decoder.next_tag() {
    Some(_) => assert_eq(decoder.read_string(), "abc")
    None => assert_true(false)
  }
  assert_true(decoder.is_empty())
  assert_eq(decoder.position(), 6)
}

///|
test "decoder on an empty message has no fields" {
  let decoder = Decoder::new(b"")
  assert_true(decoder.is_empty())
  assert_eq(decoder.next_tag(), None)
}

///|
test "decoder reads multi-byte length prefixes" {
  let payload = Bytes::make(16384, b'y')
  let encoder = Encoder::new()
  encoder.write_bytes(7, payload)
  let decoder = Decoder::new(encoder.finish())
  match decoder.next_tag() {
    Some(tag) => {
      assert_eq(tag.field_number(), 7)
      assert_eq(decoder.read_bytes(), payload)
    }
    None => assert_true(false)
  }
  assert_true(decoder.is_empty())
}
