// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
test "write_string emits tag, length, and UTF-8 payload" {
  let encoder = Encoder::new()
  encoder.write_string(1, "hello")
  assert_eq(encoder.finish(), b"\x0A\x05hello")
  assert_eq(encoder.size(), 7)
}

///|
test "write_string handles empty and non-ASCII values" {
  let empty = Encoder::new()
  empty.write_string(1, "")
  assert_eq(empty.finish(), b"\x0A\x00")

  let chinese = Encoder::new()
  chinese.write_string(1, "你好")
  assert_eq(chinese.finish(), b"\x0A\x06\xE4\xBD\xA0\xE5\xA5\xBD")

  let emoji = Encoder::new()
  emoji.write_string(2, "🚀")
  assert_eq(emoji.finish(), b"\x12\x04\xF0\x9F\x9A\x80")
}

///|
test "write_bytes preserves arbitrary byte values" {
  let encoder = Encoder::new()
  encoder.write_bytes(2, b"\x00\x01\xFF")
  assert_eq(encoder.finish(), b"\x12\x03\x00\x01\xFF")

  let empty = Encoder::new()
  empty.write_bytes(3, b"")
  assert_eq(empty.finish(), b"\x1A\x00")
}

///|
test "length-delimited fields append in call order" {
  let encoder = Encoder::new()
  encoder.write_string(1, "a")
  encoder.write_bytes(2, b"\x00")
  encoder.write_string(3, "bc")
  assert_eq(encoder.finish(), b"\x0A\x01a\x12\x01\x00\x1A\x02bc")
}

///|
test "length prefixes use multi-byte varints when needed" {
  let payload = Bytes::make(300, b'x')
  let encoder = Encoder::new()
  encoder.write_bytes(2, payload)
  let bytes = encoder.finish()
  assert_eq(bytes.length(), 303)
  assert_eq(bytes[0], b'\x12')
  assert_eq(bytes[1], b'\xAC')
  assert_eq(bytes[2], b'\x02')
  assert_eq(bytes[3:303], payload[:])
}

///|
test "length-delimited encoders validate field numbers" {
  let encoder = Encoder::new()
  assert_true(
    try {
      encoder.write_string(0, "x")
      false
    } catch {
      @types.FieldNumberOutOfRange(_) => true
      _ => false
    },
  )
  assert_true(
    try {
      encoder.write_bytes(19000, b"x")
      false
    } catch {
      @types.ReservedFieldNumber(_) => true
      _ => false
    },
  )
  assert_eq(encoder.finish(), b"")
}

///|
test "write_length_delimited is reusable for embedded payloads" {
  let nested = Encoder::new()
  nested.write_string(1, "core")
  let encoder = Encoder::new()
  encoder.write_length_delimited(5, nested.finish())
  assert_eq(encoder.finish(), b"\x2A\x06\x0A\x04core")
}
