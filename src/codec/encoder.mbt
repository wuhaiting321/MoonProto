// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Incremental Protocol Buffers encoder.
///
/// Fields are appended in call order. Length-delimited fields write a tag, a
/// varint payload length, and the payload itself. The encoder is deliberately
/// schema-free: callers choose the field number and value type explicitly, so
/// the same builder can be used by hand-written code and by generated code.
pub struct Encoder {
  buffer : @buffer.Buffer
}

///|
/// Create an empty encoder.
pub fn Encoder::new() -> Encoder {
  { buffer: @buffer.Buffer(), }
}

///|
/// Number of bytes written so far.
pub fn Encoder::size(self : Encoder) -> Int {
  self.buffer.length()
}

///|
/// Whether no field has been written yet.
pub fn Encoder::is_empty(self : Encoder) -> Bool {
  self.buffer.is_empty()
}

///|
/// Finish encoding and return an owned copy of the wire bytes.
///
/// The encoder remains usable; subsequent writes append to the same buffer.
pub fn Encoder::finish(self : Encoder) -> Bytes {
  self.buffer.to_bytes()
}

///|
/// Write a length-delimited field with an explicit payload.
///
/// This is the primitive shared by `string`, `bytes`, embedded messages, and
/// packed repeated fields. The payload length is encoded as an unsigned varint
/// immediately after the tag.
///
/// Raises `EncodeError` when `field_number` is invalid.
pub fn Encoder::write_length_delimited(
  self : Encoder,
  field_number : Int,
  payload : Bytes,
) -> Unit raise @types.EncodeError {
  let tag = @wire.Tag::new(field_number, @wire.WireType::LengthDelimited)
  @wire.write_tag(self.buffer, tag)
  @wire.write_uvarint(self.buffer, payload.length().to_uint64())
  self.buffer.write_bytes(payload)
}

///|
/// Write a protobuf `string` field.
///
/// MoonBit strings are encoded as UTF-8, matching the protobuf wire format.
pub fn Encoder::write_string(
  self : Encoder,
  field_number : Int,
  value : String,
) -> Unit raise @types.EncodeError {
  self.write_length_delimited(field_number, @utf8.encode(value))
}

///|
/// Write a protobuf `bytes` field verbatim.
pub fn Encoder::write_bytes(
  self : Encoder,
  field_number : Int,
  value : Bytes,
) -> Unit raise @types.EncodeError {
  self.write_length_delimited(field_number, value)
}
