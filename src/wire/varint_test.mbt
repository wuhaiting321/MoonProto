// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Decode a single varint from the start of `bytes`, discarding the end offset.
fn decode_one(bytes : Bytes) -> UInt64 raise @types.DecodeError {
  let (value, _) = read_uvarint(bytes, 0)
  value
}

///|
/// Assert that decoding `bytes` raises a specific decode error variant.
test "read_uvarint rejects empty and truncated input" {
  assert_true(
    try {
      let _ = read_uvarint(b"", 0)
      false
    } catch {
      @types.Truncated(..) => true
      _ => false
    },
  )
  assert_true(
    try {
      let _ = read_uvarint(b"\x80", 0)
      false
    } catch {
      @types.Truncated(..) => true
      _ => false
    },
  )
  assert_true(
    try {
      let _ = read_uvarint(b"\x80\x80\x80", 0)
      false
    } catch {
      @types.Truncated(..) => true
      _ => false
    },
  )
}

///|
test "read_uvarint rejects negative and past-end offsets" {
  assert_true(
    try {
      let _ = read_uvarint(b"\x01", -1)
      false
    } catch {
      @types.Truncated(..) => true
      _ => false
    },
  )
  assert_true(
    try {
      let _ = read_uvarint(b"\x01", 2)
      false
    } catch {
      @types.Truncated(..) => true
      _ => false
    },
  )
}

///|
test "read_uvarint rejects varints longer than ten bytes" {
  assert_true(
    try {
      let _ = read_uvarint(b"\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x00", 0)
      false
    } catch {
      @types.VarintTooLong(..) => true
      _ => false
    },
  )
}

///|
test "read_uvarint rejects tenth-byte overflow" {
  assert_true(
    try {
      let _ = read_uvarint(b"\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x02", 0)
      false
    } catch {
      @types.VarintOverflow(..) => true
      _ => false
    },
  )
}

///|
test "uvarint_len matches canonical encodings" {
  assert_eq(uvarint_len(0UL), 1)
  assert_eq(uvarint_len(1UL), 1)
  assert_eq(uvarint_len(127UL), 1)
  assert_eq(uvarint_len(128UL), 2)
  assert_eq(uvarint_len(16383UL), 2)
  assert_eq(uvarint_len(16384UL), 3)
  assert_eq(uvarint_len(0xFFFFFFFFUL), 5)
  assert_eq(uvarint_len(0x100000000UL), 5)
  assert_eq(uvarint_len(0x100000001UL), 5)
  assert_eq(uvarint_len(0x7FFFFFFFFFFFFFFFUL), 9)
  assert_eq(uvarint_len(0x8000000000000000UL), 10)
  assert_eq(uvarint_len(0xFFFFFFFFFFFFFFFFUL), 10)
}

///|
test "encode_uvarint matches protobuf reference vectors" {
  assert_eq(encode_uvarint(0UL), b"\x00")
  assert_eq(encode_uvarint(1UL), b"\x01")
  assert_eq(encode_uvarint(127UL), b"\x7F")
  assert_eq(encode_uvarint(128UL), b"\x80\x01")
  assert_eq(encode_uvarint(300UL), b"\xAC\x02")
  assert_eq(encode_uvarint(16383UL), b"\xFF\x7F")
  assert_eq(encode_uvarint(16384UL), b"\x80\x80\x01")
  assert_eq(encode_uvarint(0xFFFFFFFFUL), b"\xFF\xFF\xFF\xFF\x0F")
  assert_eq(
    encode_uvarint(0x8000000000000000UL),
    b"\x80\x80\x80\x80\x80\x80\x80\x80\x80\x01",
  )
  assert_eq(
    encode_uvarint(0xFFFFFFFFFFFFFFFFUL),
    b"\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x01",
  )
}

///|
test "read_uvarint matches protobuf reference vectors" {
  let vectors : Array[(Bytes, UInt64)] = [
    (b"\x00", 0UL),
    (b"\x01", 1UL),
    (b"\x7F", 127UL),
    (b"\x80\x01", 128UL),
    (b"\xAC\x02", 300UL),
    (b"\xFF\x7F", 16383UL),
    (b"\x80\x80\x01", 16384UL),
    (b"\xFF\xFF\xFF\xFF\x0F", 0xFFFFFFFFUL),
    (b"\x80\x80\x80\x80\x80\x80\x80\x80\x80\x01", 0x8000000000000000UL),
    (b"\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x01", 0xFFFFFFFFFFFFFFFFUL),
  ]
  for vector in vectors {
    let (value, next) = read_uvarint(vector.0, 0)
    assert_eq(value, vector.1)
    assert_eq(next, vector.0.length())
  }
}

///|
test "read_uvarint honours offsets and reports the next position" {
  let bytes = b"\xAA\xAC\x02\x2B"
  let (value, next) = read_uvarint(bytes, 1)
  assert_eq(value, 300UL)
  assert_eq(next, 3)
  let (second, third) = read_uvarint(bytes, 3)
  assert_eq(second, 0x2BUL)
  assert_eq(third, 4)
}

///|
test "read_uvarint accepts non-minimal encodings" {
  let (value, next) = read_uvarint(b"\x80\x00", 0)
  assert_eq(value, 0UL)
  assert_eq(next, 2)
  let (second, second_next) = read_uvarint(b"\x81\x80\x00", 0)
  assert_eq(second, 1UL)
  assert_eq(second_next, 3)
}

///|
test "uvarint round-trips a representative value set" {
  let values : Array[UInt64] = [
    0UL, 1UL, 2UL, 127UL, 128UL, 255UL, 256UL, 300UL, 16383UL, 16384UL, 0xFFFFUL,
    0x10000UL, 0xFFFFFFFFUL, 0x100000000UL, 0x123456789ABCDEFUL, 0x7FFFFFFFFFFFFFFFUL,
    0x8000000000000000UL, 0xFFFFFFFFFFFFFFFFUL,
  ]
  for value in values {
    let encoded = encode_uvarint(value)
    assert_eq(encoded.length(), uvarint_len(value))
    assert_eq(decode_one(encoded), value)
  }
}

///|
test "zigzag32 matches reference values" {
  assert_eq(zigzag_encode32(0), 0U)
  assert_eq(zigzag_encode32(-1), 1U)
  assert_eq(zigzag_encode32(1), 2U)
  assert_eq(zigzag_encode32(-2), 3U)
  assert_eq(zigzag_encode32(2), 4U)
  assert_eq(zigzag_encode32(2147483647), 4294967294U)
  assert_eq(zigzag_encode32(-2147483648), 4294967295U)
  assert_eq(zigzag_decode32(0U), 0)
  assert_eq(zigzag_decode32(1U), -1)
  assert_eq(zigzag_decode32(2U), 1)
  assert_eq(zigzag_decode32(3U), -2)
  assert_eq(zigzag_decode32(4294967295U), -2147483648)
}

///|
test "zigzag64 matches reference values" {
  assert_eq(zigzag_encode64(0L), 0UL)
  assert_eq(zigzag_encode64(-1L), 1UL)
  assert_eq(zigzag_encode64(1L), 2UL)
  assert_eq(zigzag_encode64(-2L), 3UL)
  assert_eq(zigzag_encode64(9223372036854775807L), 18446744073709551614UL)
  assert_eq(zigzag_encode64(-9223372036854775808L), 18446744073709551615UL)
  assert_eq(zigzag_decode64(0UL), 0L)
  assert_eq(zigzag_decode64(1UL), -1L)
  assert_eq(zigzag_decode64(2UL), 1L)
  assert_eq(zigzag_decode64(18446744073709551615UL), -9223372036854775808L)
}

///|
test "sint32 and sint64 encode as compact zigzag varints" {
  assert_eq(encode_uvarint(sint32_to_u64(0)), b"\x00")
  assert_eq(encode_uvarint(sint32_to_u64(-1)), b"\x01")
  assert_eq(encode_uvarint(sint32_to_u64(1)), b"\x02")
  assert_eq(encode_uvarint(sint32_to_u64(-2147483648)), b"\xFF\xFF\xFF\xFF\x0F")
  assert_eq(encode_uvarint(sint64_to_u64(-1L)), b"\x01")
  assert_eq(
    encode_uvarint(sint64_to_u64(-9223372036854775808L)),
    b"\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x01",
  )
  assert_eq(
    encode_uvarint(sint64_to_u64(9223372036854775807L)),
    b"\xFE\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x01",
  )
}

///|
test "int32 sign extension uses ten-byte varints" {
  assert_eq(int32_to_u64(-1), 0xFFFFFFFFFFFFFFFFUL)
  assert_eq(encode_uvarint(int32_to_u64(-1)).length(), 10)
  assert_eq(encode_uvarint(int32_to_u64(-2)).length(), 10)
  assert_eq(encode_uvarint(int32_to_u64(-2147483648)).length(), 10)
  assert_eq(encode_uvarint(int32_to_u64(2147483647)), b"\xFF\xFF\xFF\xFF\x07")
  assert_eq(encode_uvarint(int32_to_u64(0)), b"\x00")
}

///|
test "typed decode helpers round-trip boundary values" {
  let int32_values : Array[Int32] = [
    0, 1, -1, 2147483647, -2147483648, 300, -300,
  ]
  for value in int32_values {
    let payload = int32_to_u64(value)
    assert_eq(u64_to_int32(payload), value)
    let decoded = decode_one(encode_uvarint(payload))
    assert_eq(u64_to_int32(decoded), value)
  }
  let int64_values : Array[Int64] = [
    0L, 1L, -1L, 9223372036854775807L, -9223372036854775808L, 0x123456789ABCDEFL,
  ]
  for value in int64_values {
    let payload = int64_to_u64(value)
    assert_eq(u64_to_int64(payload), value)
    let decoded = decode_one(encode_uvarint(payload))
    assert_eq(u64_to_int64(decoded), value)
  }
  let uint32_values : Array[UInt32] = [0U, 1U, 127U, 128U, 4294967295U]
  for value in uint32_values {
    let payload = uint32_to_u64(value)
    assert_eq(u64_to_uint32(payload), value)
    assert_eq(u64_to_uint32(decode_one(encode_uvarint(payload))), value)
  }
  let sint32_values : Array[Int32] = [0, -1, 1, 2147483647, -2147483648]
  for value in sint32_values {
    assert_eq(
      u64_to_sint32(decode_one(encode_uvarint(sint32_to_u64(value)))),
      value,
    )
  }
  let sint64_values : Array[Int64] = [
    0L, -1L, 1L, 9223372036854775807L, -9223372036854775808L,
  ]
  for value in sint64_values {
    assert_eq(
      u64_to_sint64(decode_one(encode_uvarint(sint64_to_u64(value)))),
      value,
    )
  }
}

///|
test "write_uvarint appends without disturbing existing bytes" {
  let buffer = @buffer.Buffer()
  buffer.write_byte(b'\xAA')
  write_uvarint(buffer, 300UL)
  buffer.write_byte(b'\xBB')
  assert_eq(buffer.to_bytes(), b"\xAA\xAC\x02\xBB")
}
