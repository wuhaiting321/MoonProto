// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Maximum nested-message depth accepted by `Decoder::read_submessage`.
pub const MAX_MESSAGE_DEPTH : Int32 = 100

///|
/// Nesting depth of this decoder. A top-level decoder has depth zero.
pub fn Decoder::depth(self : Decoder) -> Int32 {
  self.depth
}

///|
/// Write an embedded message field from another encoder.
///
/// The nested encoder is finished immediately and its bytes become the
/// length-delimited payload. The caller can continue using the nested encoder
/// for other purposes, because `finish` returns a copy.
///
/// This method is the recursive building block for message trees: build each
/// child encoder first, then embed it in its parent.
pub fn Encoder::write_message(
  self : Encoder,
  field_number : Int32,
  message : Encoder,
) -> Unit raise @types.EncodeError {
  self.write_length_delimited(field_number, message.finish())
}

///|
/// Enter the embedded message identified by `tag`.
///
/// Returns a child decoder whose window is exactly the declared payload, and
/// advances the parent past that payload. The child inherits the absolute byte
/// offsets of the parent and has its depth increased by one.
///
/// Raises `DecodeError` when `tag` is not length-delimited, the declared length
/// exceeds the remaining input, or the configured nesting limit is reached.
pub fn Decoder::read_submessage(
  self : Decoder,
  tag : @wire.Tag,
) -> Decoder raise @types.DecodeError {
  if tag.wire_type() != @wire.WireType::LengthDelimited {
    raise @types.UnexpectedWireType(
      expected=@wire.WireType::LengthDelimited.to_int(),
      actual=tag.wire_type().to_int(),
    )
  }
  if self.depth >= MAX_MESSAGE_DEPTH {
    raise @types.RecursionLimitExceeded(limit=MAX_MESSAGE_DEPTH)
  }
  { reader: self.reader.read_subreader(), depth: self.depth + 1, }
}
