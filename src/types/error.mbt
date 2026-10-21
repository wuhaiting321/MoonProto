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
} derive(Debug, Eq)

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
} derive(Debug, Eq)
