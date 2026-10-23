// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Absolute byte offset carried by a decode failure, when the variant records
/// one.
///
/// `RecursionLimitExceeded` is depth-based and `UnknownWireType` raised through
/// `WireType::from_int` without a cursor carries `-1`; both return `None`.
pub fn error_offset(error : @types.DecodeError) -> Int32? {
  let offset = match error {
    @types.Truncated(offset~, ..)
    | @types.VarintTooLong(offset~)
    | @types.VarintOverflow(offset~)
    | @types.UnknownWireType(offset~, ..)
    | @types.InvalidFieldNumber(offset~, ..)
    | @types.TagValueOutOfRange(offset~, ..)
    | @types.LengthOutOfBounds(offset~, ..)
    | @types.UnexpectedEndGroup(offset~)
    | @types.MismatchedEndGroup(offset~, ..)
    | @types.UnterminatedGroup(offset~)
    | @types.FieldLimitExceeded(offset~, ..)
    | @types.InvalidUtf8(offset~)
    | @types.UnexpectedWireType(offset~, ..)
    | @types.InvalidPackedLength(offset~, ..) => offset
    @types.RecursionLimitExceeded(..) => -1
  }
  if offset >= 0 {
    Some(offset)
  } else {
    None
  }
}

///|
/// Render a decode failure together with the bytes around the failing offset.
///
/// The report contains three lines: the `message()` text, the absolute offset,
/// and a short hex window whose caret points at the byte where decoding
/// stopped. Errors without an offset return just `message()`.
pub fn error_context(
  bytes : Bytes,
  error : @types.DecodeError,
  before~ : Int32 = 4,
  after~ : Int32 = 4,
) -> String {
  let message = error.message()
  let offset = match error_offset(error) {
    Some(offset) => offset
    None => return message
  }
  let length = bytes.length()
  let clamped = if offset < length { offset } else { length }
  let start = if clamped > before { clamped - before } else { 0 }
  let mut end = clamped + after
  if end > length {
    end = length
  }
  let mut hex = ""
  for index in start..<end {
    if index > start {
      hex = hex + " "
    }
    hex = hex + bytes[index].to_hex()
  }
  let mut marker = ""
  for _ in 0..<(clamped - start) {
    marker = marker + "   "
  }
  marker = marker + "^^"
  message +
  "\n  offset " +
  offset.to_string() +
  " of " +
  length.to_string() +
  "\n   " +
  hex +
  "\n   " +
  marker
}
