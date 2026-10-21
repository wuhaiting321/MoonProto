// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Maximum number of bytes in a base-128 varint that encodes a 64-bit value.
pub const MAX_VARINT_BYTES : Int = 10

///|
/// Number of payload bits carried by every byte except the last one.
const VARINT_PAYLOAD_BITS : Int = 7

///|
/// Number of bytes needed to encode `value` as an unsigned varint.
///
/// The result is always between 1 and 10, including for `0`.
///
/// ```mbt check
/// test "uvarint_len boundaries" {
///   assert_eq(uvarint_len(0UL), 1)
///   assert_eq(uvarint_len(127UL), 1)
///   assert_eq(uvarint_len(128UL), 2)
///   assert_eq(uvarint_len(0xFFFFFFFFFFFFFFFFUL), 10)
/// }
/// ```
pub fn uvarint_len(value : UInt64) -> Int {
  let mut remaining = value
  let mut length = 1
  while remaining >= 0x80UL {
    remaining = remaining >> VARINT_PAYLOAD_BITS
    length = length + 1
  }
  length
}

///|
/// Append the unsigned base-128 varint encoding of `value` to `buffer`.
///
/// The encoder is the canonical protobuf encoder: seven payload bits per
/// byte, least-significant group first, with the high bit set on every byte
/// that is followed by another one.
pub fn write_uvarint(buffer : @buffer.Buffer, value : UInt64) -> Unit {
  let mut remaining = value
  while remaining >= 0x80UL {
    buffer.write_byte(((remaining & 0x7FUL) | 0x80UL).to_byte())
    remaining = remaining >> VARINT_PAYLOAD_BITS
  }
  buffer.write_byte(remaining.to_byte())
}

///|
/// Encode `value` as a standalone unsigned varint byte sequence.
pub fn encode_uvarint(value : UInt64) -> Bytes {
  let buffer = @buffer.Buffer(size_hint=uvarint_len(value))
  write_uvarint(buffer, value)
  buffer.to_bytes()
}

///|
/// Decode one unsigned varint starting at `offset`.
///
/// Returns the decoded 64-bit value together with the offset of the first byte
/// after the varint. The function accepts non-minimal encodings, matching the
/// behaviour of the reference protobuf implementations, but rejects varints
/// that need more than ten bytes or whose tenth byte overflows 64 bits.
///
/// Raises `DecodeError` if the input is truncated or the encoding is invalid.
pub fn read_uvarint(
  bytes : Bytes,
  offset : Int,
) -> (UInt64, Int) raise @types.DecodeError {
  let length = bytes.length()
  if offset < 0 || offset > length {
    raise @types.Truncated(offset~, needed=1, available=0)
  }
  let mut position = offset
  let mut value = 0UL
  for index in 0..<MAX_VARINT_BYTES {
    if position >= length {
      raise @types.Truncated(offset~, needed=1, available=length - offset)
    }
    let byte = bytes[position]
    let payload = byte.to_uint64()
    position = position + 1
    if index == MAX_VARINT_BYTES - 1 {
      if payload >= 0x80UL {
        raise @types.VarintTooLong(offset~)
      }
      if payload > 1UL {
        raise @types.VarintOverflow(offset~)
      }
      return (value | (payload << 63), position)
    }
    value = value | ((payload & 0x7FUL) << (index * VARINT_PAYLOAD_BITS))
    if payload < 0x80UL {
      return (value, position)
    }
  }
  raise @types.VarintTooLong(offset~)
}

///|
/// Map a signed 32-bit integer to the unsigned 32-bit zigzag code.
///
/// Zigzag maps small absolute values to small varints: `0 -> 0`, `-1 -> 1`,
/// `1 -> 2`, `-2 -> 3`, and so on.
pub fn zigzag_encode32(value : Int) -> UInt {
  ((value << 1) ^ (value >> 31)).reinterpret_as_uint()
}

///|
/// Recover a signed 32-bit integer from its unsigned zigzag code.
pub fn zigzag_decode32(value : UInt) -> Int {
  (value >> 1).reinterpret_as_int() ^ -(value & 1U).reinterpret_as_int()
}

///|
/// Map a signed 64-bit integer to the unsigned 64-bit zigzag code.
pub fn zigzag_encode64(value : Int64) -> UInt64 {
  ((value << 1) ^ (value >> 63)).reinterpret_as_uint64()
}

///|
/// Recover a signed 64-bit integer from its unsigned zigzag code.
pub fn zigzag_decode64(value : UInt64) -> Int64 {
  (value >> 1).reinterpret_as_int64() ^ -(value & 1UL).reinterpret_as_int64()
}

///|
/// Convert a protobuf `int32` value to the varint payload it is sent as.
///
/// Negative `int32` values are sign-extended to 64 bits, which is why they
/// occupy ten bytes on the wire.
pub fn int32_to_u64(value : Int) -> UInt64 {
  value.to_int64().reinterpret_as_uint64()
}

///|
/// Convert a protobuf `int64` value to its varint payload.
pub fn int64_to_u64(value : Int64) -> UInt64 {
  value.reinterpret_as_uint64()
}

///|
/// Convert a protobuf `uint32` value to its varint payload.
pub fn uint32_to_u64(value : UInt) -> UInt64 {
  value.to_uint64()
}

///|
/// Convert a protobuf `sint32` value to its zigzag varint payload.
pub fn sint32_to_u64(value : Int) -> UInt64 {
  zigzag_encode32(value).to_uint64()
}

///|
/// Convert a protobuf `sint64` value to its zigzag varint payload.
pub fn sint64_to_u64(value : Int64) -> UInt64 {
  zigzag_encode64(value)
}

///|
/// Interpret a varint payload as a protobuf `int32`, truncating to 32 bits.
pub fn u64_to_int32(value : UInt64) -> Int {
  value.to_uint().reinterpret_as_int()
}

///|
/// Interpret a varint payload as a protobuf `int64`.
pub fn u64_to_int64(value : UInt64) -> Int64 {
  value.reinterpret_as_int64()
}

///|
/// Interpret a varint payload as a protobuf `uint32`, truncating to 32 bits.
pub fn u64_to_uint32(value : UInt64) -> UInt {
  value.to_uint()
}

///|
/// Interpret a zigzag varint payload as a protobuf `sint32`.
pub fn u64_to_sint32(value : UInt64) -> Int {
  zigzag_decode32(value.to_uint())
}

///|
/// Interpret a zigzag varint payload as a protobuf `sint64`.
pub fn u64_to_sint64(value : UInt64) -> Int64 {
  zigzag_decode64(value)
}
