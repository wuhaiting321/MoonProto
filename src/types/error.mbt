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
  Truncated(offset~ : Int32, needed~ : Int32, available~ : Int32)
  /// A varint continued past the ten bytes allowed for a 64-bit value.
  VarintTooLong(offset~ : Int32)
  /// The tenth varint byte carried bits outside the 64-bit range.
  VarintOverflow(offset~ : Int32)
  /// A tag used a wire type outside the six defined protobuf wire types.
  UnknownWireType(value~ : Int32)
  /// A tag carried field number zero or a number above the protobuf maximum.
  InvalidFieldNumber(field_number~ : Int32)
  /// A tag varint carried more than the 32 bits a valid tag can occupy.
  TagValueOutOfRange(value~ : UInt64)
  /// A length-delimited field declared more bytes than the input contains.
  LengthOutOfBounds(offset~ : Int32, length~ : UInt64, remaining~ : Int32)
  /// A group was closed without a matching start-group tag.
  UnexpectedEndGroup(offset~ : Int32)
  /// An end-group tag named a different field than its start-group tag.
  MismatchedEndGroup(offset~ : Int32, expected~ : Int32, actual~ : Int32)
  /// The input ended while a start-group tag was still open.
  UnterminatedGroup(offset~ : Int32)
  /// Nested groups exceeded the configured safety limit.
  RecursionLimitExceeded(limit~ : Int32)
  /// A string field contained bytes that are not valid UTF-8.
  InvalidUtf8(offset~ : Int32)
  /// A field tag used a wire type that cannot carry the requested scalar.
  UnexpectedWireType(expected~ : Int32, actual~ : Int32)
  /// A fixed-width packed payload was not a multiple of its element width.
  InvalidPackedLength(length~ : Int32, element_width~ : Int32)
} derive(Debug, Eq)

///|
/// Explicit trait-method promotion for the derived `Debug` implementation.
pub extend DecodeError with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Explicit trait-method promotion for the derived `Eq` implementation.
pub extend DecodeError with Eq::{equal, not_equal}

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
  FieldNumberOutOfRange(field_number~ : Int32)
  /// A field number fell inside the implementation-reserved range 19000..19999.
  ReservedFieldNumber(field_number~ : Int32)
  /// A packed array mixed scalars of different protobuf types.
  PackedTypeMismatch(expected~ : String, actual~ : String)
} derive(Debug, Eq)

///|
/// Explicit trait-method promotion for the derived `Debug` implementation.
pub extend EncodeError with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Explicit trait-method promotion for the derived `Eq` implementation.
pub extend EncodeError with Eq::{equal, not_equal}

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
