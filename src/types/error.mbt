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
} derive(Debug, Eq)
