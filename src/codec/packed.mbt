// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Write a packed repeated scalar field.
///
/// Every element is encoded back-to-back with no per-element tags, and the
/// concatenated payload is written as one length-delimited field. An empty
/// array writes nothing, matching proto3's omission of empty repeated fields.
///
/// Raises `EncodeError` when `field_number` is invalid or the array mixes
/// different scalar types. `string` and `bytes` cannot be packed.
pub fn Encoder::write_packed_scalar_field(
  self : Encoder,
  field_number : Int32,
  values : Array[@types.ScalarValue],
) -> Unit raise @types.EncodeError {
  let tag = @wire.Tag::new(field_number, @wire.WireType::LengthDelimited)
  if values.is_empty() {
    return
  }
  let element_type = values[0].scalar_type()
  let mut payload_length = 0
  for value in values {
    let actual = value.scalar_type()
    if actual != element_type {
      raise @types.PackedTypeMismatch(
        expected=element_type.name(),
        actual=actual.name(),
      )
    }
    payload_length = payload_length + scalar_payload_len(value)
  }
  @wire.write_tag(self.buffer, tag)
  @wire.write_uvarint(self.buffer, payload_length.to_uint64())
  for value in values {
    write_scalar_payload(self.buffer, value)
  }
}

///|
/// Read a packed repeated scalar field.
///
/// `tag` must be length-delimited. The payload is parsed inside a subreader, so
/// the enclosing message stays aligned even when the packed data is malformed.
///
/// Raises `DecodeError` when the wire type is wrong, a fixed-width payload is
/// not a multiple of the element size, or an element is truncated.
pub fn Decoder::read_packed_scalar_field(
  self : Decoder,
  tag : @wire.Tag,
  scalar_type : @types.ScalarType,
) -> Array[@types.ScalarValue] raise @types.DecodeError {
  if tag.wire_type() != @wire.WireType::LengthDelimited {
    raise @types.UnexpectedWireType(
      expected=@wire.WireType::LengthDelimited.to_int(),
      actual=tag.wire_type().to_int(),
    )
  }
  let subreader = self.reader.read_subreader()
  let width = match scalar_type {
    @types.ScalarType::Fixed32
    | @types.ScalarType::SFixed32
    | @types.ScalarType::Float => 4
    @types.ScalarType::Fixed64
    | @types.ScalarType::SFixed64
    | @types.ScalarType::Double => 8
    _ => 0
  }
  if width > 0 {
    let remaining = subreader.remaining()
    if remaining % width != 0 {
      raise @types.InvalidPackedLength(length=remaining, element_width=width)
    }
  }
  let values : Array[@types.ScalarValue] = []
  while !subreader.is_empty() {
    values.push(read_scalar_from(subreader, scalar_type))
  }
  values
}
