// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Errors raised while decoding Protocol Buffers wire bytes.
///
/// The variants carry the byte offset at which the failure was detected so
/// that callers can report actionable diagnostics. The error set is expanded
/// as higher-level wire and schema rules are added.
pub(all) suberror DecodeError {
  /// The input ended before the requested range could be read.
  Truncated(offset~ : Int, needed~ : Int, available~ : Int)
  /// A varint continued past the ten bytes allowed for a 64-bit value.
  VarintTooLong(offset~ : Int)
  /// The tenth varint byte carried bits outside the 64-bit range.
  VarintOverflow(offset~ : Int)
  /// A tag used a wire type outside the six defined protobuf wire types.
  UnknownWireType(value~ : Int)
  /// A tag carried field number zero or a number above the protobuf maximum.
  InvalidFieldNumber(field_number~ : Int)
  /// A tag varint carried more than the 32 bits a valid tag can occupy.
  TagValueOutOfRange(value~ : UInt64)
  /// A length-delimited field declared more bytes than the input contains.
  LengthOutOfBounds(offset~ : Int, length~ : UInt64, remaining~ : Int)
  /// A group was closed without a matching start-group tag.
  UnexpectedEndGroup(offset~ : Int)
  /// An end-group tag named a different field than its start-group tag.
  MismatchedEndGroup(offset~ : Int, expected~ : Int, actual~ : Int)
  /// The input ended while a start-group tag was still open.
  UnterminatedGroup(offset~ : Int)
  /// Nested groups exceeded the configured safety limit.
  RecursionLimitExceeded(limit~ : Int)
  /// A string field contained bytes that are not valid UTF-8.
  InvalidUtf8(offset~ : Int)
  /// A field tag used a wire type that cannot carry the requested scalar.
  UnexpectedWireType(expected~ : Int, actual~ : Int)
  /// A fixed-width packed payload was not a multiple of its element width.
  InvalidPackedLength(length~ : Int, element_width~ : Int)
} derive(Debug, Eq)

///|
/// Human-readable diagnostic for a decode failure.
///
/// Every message names the failing construct and, where available, the byte
/// offset at which it was detected.
pub fn DecodeError::message(self : DecodeError) -> String {
  match self {
    Truncated(offset~, needed~, available~) =>
      "truncated input at offset " +
      offset.to_string() +
      ": needed " +
      needed.to_string() +
      " bytes, " +
      available.to_string() +
      " available"
    VarintTooLong(offset~) =>
      "varint at offset " + offset.to_string() + " exceeds 10 bytes"
    VarintOverflow(offset~) =>
      "varint at offset " + offset.to_string() + " overflows 64 bits"
    UnknownWireType(value~) => "unknown wire type " + value.to_string()
    InvalidFieldNumber(field_number~) =>
      "invalid field number " + field_number.to_string()
    TagValueOutOfRange(value~) =>
      "tag value " + value.to_string() + " exceeds 32 bits"
    LengthOutOfBounds(offset~, length~, remaining~) =>
      "length " +
      length.to_string() +
      " at offset " +
      offset.to_string() +
      " exceeds " +
      remaining.to_string() +
      " remaining bytes"
    UnexpectedEndGroup(offset~) =>
      "unexpected end-group at offset " + offset.to_string()
    MismatchedEndGroup(offset~, expected~, actual~) =>
      "end-group field " +
      actual.to_string() +
      " does not match start-group field " +
      expected.to_string() +
      " at offset " +
      offset.to_string()
    UnterminatedGroup(offset~) =>
      "unterminated group at offset " + offset.to_string()
    RecursionLimitExceeded(limit~) =>
      "recursion limit " + limit.to_string() + " exceeded"
    InvalidUtf8(offset~) => "invalid UTF-8 at offset " + offset.to_string()
    UnexpectedWireType(expected~, actual~) =>
      "unexpected wire type " +
      actual.to_string() +
      ", expected " +
      expected.to_string()
    InvalidPackedLength(length~, element_width~) =>
      "packed length " +
      length.to_string() +
      " is not a multiple of " +
      element_width.to_string()
  }
}

///|
/// Errors raised while encoding Protocol Buffers messages.
///
/// Encoding never inspects untrusted input, so these errors describe invalid
/// schema or field choices made by the caller.
pub(all) suberror EncodeError {
  /// A field number was zero or above the protobuf maximum.
  FieldNumberOutOfRange(field_number~ : Int)
  /// A field number fell inside the implementation-reserved range 19000..19999.
  ReservedFieldNumber(field_number~ : Int)
  /// A packed array mixed scalars of different protobuf types.
  PackedTypeMismatch(expected~ : String, actual~ : String)
} derive(Debug, Eq)

///|
/// Human-readable diagnostic for an encode failure.
pub fn EncodeError::message(self : EncodeError) -> String {
  match self {
    FieldNumberOutOfRange(field_number~) =>
      "field number " + field_number.to_string() + " is outside 1..536870911"
    ReservedFieldNumber(field_number~) =>
      "field number " + field_number.to_string() + " is reserved"
    PackedTypeMismatch(expected~, actual~) =>
      "packed field mixes " + actual + " with " + expected
  }
}
