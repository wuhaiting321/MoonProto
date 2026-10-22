// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Incremental Protocol Buffers decoder.
///
/// The decoder walks a message field by field. `next_tag` yields the next tag
/// and leaves the cursor on the payload; the caller then reads the payload with
/// the method matching the wire type, or skips it with `skip_tag`.
///
/// Length-delimited payloads are bounded by their declared length, so a nested
/// or malformed payload can never read into the following field.
pub struct Decoder {
  reader : @wire.WireReader
  depth : Int
}

///|
/// Create a decoder over a complete message.
pub fn Decoder::new(bytes : Bytes) -> Decoder {
  { reader: @wire.WireReader::new(bytes), depth: 0, }
}

///|
/// Create a decoder over the window `[start, end)` of `bytes`.
pub fn Decoder::new_limited(
  bytes : Bytes,
  start : Int,
  end : Int,
) -> Decoder raise @types.DecodeError {
  { reader: @wire.WireReader::new_limited(bytes, start, end), depth: 0, }
}

///|
/// Current absolute read offset in the underlying byte array.
pub fn Decoder::position(self : Decoder) -> Int {
  self.reader.position()
}

///|
/// Number of bytes left in this decoder's window.
pub fn Decoder::remaining(self : Decoder) -> Int {
  self.reader.remaining()
}

///|
/// Whether every field in the window has been consumed.
pub fn Decoder::is_empty(self : Decoder) -> Bool {
  self.reader.is_empty()
}

///|
/// Read the next tag, or `None` when the message is complete.
///
/// The cursor is left on the first payload byte. Callers must consume or skip
/// that payload before asking for another tag.
pub fn Decoder::next_tag(self : Decoder) -> @wire.Tag? raise @types.DecodeError {
  if self.reader.is_empty() {
    None
  } else {
    Some(self.reader.next_tag())
  }
}

///|
/// Read a length-delimited payload as raw bytes.
///
/// This is the decoder counterpart of `Encoder::write_bytes`.
pub fn Decoder::read_bytes(self : Decoder) -> Bytes raise @types.DecodeError {
  let length = self.reader.read_length()
  self.reader.read_bytes(length)
}

///|
/// Read a length-delimited payload and decode it as UTF-8.
///
/// Raises `DecodeError` when the payload is truncated or contains malformed
/// UTF-8.
pub fn Decoder::read_string(self : Decoder) -> String raise @types.DecodeError {
  let length = self.reader.read_length()
  let offset = self.reader.position()
  let payload = self.reader.read_bytes(length)
  @utf8.decode(payload) catch {
    @utf8.Malformed(_) => raise @types.InvalidUtf8(offset~)
  }
}

///|
/// Skip the payload of the field identified by `tag`.
///
/// Safe to use for unknown fields, including deprecated groups.
pub fn Decoder::skip_tag(
  self : Decoder,
  tag : @wire.Tag,
) -> Unit raise @types.DecodeError {
  self.reader.skip_tag(tag)
}
