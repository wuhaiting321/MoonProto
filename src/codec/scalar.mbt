// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// The wire type used by a protobuf scalar type.
pub fn scalar_wire_type(scalar_type : @types.ScalarType) -> @wire.WireType {
  match scalar_type {
    @types.ScalarType::Double => @wire.WireType::Fixed64
    @types.ScalarType::Float => @wire.WireType::Fixed32
    @types.ScalarType::Fixed32 => @wire.WireType::Fixed32
    @types.ScalarType::SFixed32 => @wire.WireType::Fixed32
    @types.ScalarType::Fixed64 => @wire.WireType::Fixed64
    @types.ScalarType::SFixed64 => @wire.WireType::Fixed64
    @types.ScalarType::Int32 => @wire.WireType::Varint
    @types.ScalarType::Int64 => @wire.WireType::Varint
    @types.ScalarType::UInt32 => @wire.WireType::Varint
    @types.ScalarType::UInt64 => @wire.WireType::Varint
    @types.ScalarType::SInt32 => @wire.WireType::Varint
    @types.ScalarType::SInt64 => @wire.WireType::Varint
    @types.ScalarType::Bool => @wire.WireType::Varint
    @types.ScalarType::Enum => @wire.WireType::Varint
  }
}

///|
/// Number of payload bytes a scalar occupies on the wire, excluding its tag.
pub fn scalar_payload_len(value : @types.ScalarValue) -> Int32 {
  match value {
    @types.ScalarValue::Double(_) => 8
    @types.ScalarValue::Float(_) => 4
    @types.ScalarValue::Fixed32(_) => 4
    @types.ScalarValue::SFixed32(_) => 4
    @types.ScalarValue::Fixed64(_) => 8
    @types.ScalarValue::SFixed64(_) => 8
    @types.ScalarValue::Int32(v) => @wire.uvarint_len(@wire.int32_to_u64(v))
    @types.ScalarValue::Int64(v) => @wire.uvarint_len(@wire.int64_to_u64(v))
    @types.ScalarValue::UInt32(v) => @wire.uvarint_len(@wire.uint32_to_u64(v))
    @types.ScalarValue::UInt64(v) => @wire.uvarint_len(v)
    @types.ScalarValue::SInt32(v) => @wire.uvarint_len(@wire.sint32_to_u64(v))
    @types.ScalarValue::SInt64(v) => @wire.uvarint_len(@wire.sint64_to_u64(v))
    @types.ScalarValue::Bool(_) => 1
    @types.ScalarValue::Enum(v) => @wire.uvarint_len(@wire.int32_to_u64(v))
  }
}

///|
/// Append the wire payload of a scalar, without a tag or length prefix.
fn write_scalar_payload(
  buffer : @buffer.Buffer,
  value : @types.ScalarValue,
) -> Unit {
  match value {
    @types.ScalarValue::Double(v) => buffer.write_double_le(v)
    @types.ScalarValue::Float(v) => buffer.write_float_le(v)
    @types.ScalarValue::Fixed32(v) => buffer.write_uint_le(v)
    @types.ScalarValue::SFixed32(v) =>
      buffer.write_uint_le(v.reinterpret_as_uint())
    @types.ScalarValue::Fixed64(v) => buffer.write_uint64_le(v)
    @types.ScalarValue::SFixed64(v) =>
      buffer.write_uint64_le(v.reinterpret_as_uint64())
    @types.ScalarValue::Int32(v) =>
      @wire.write_uvarint(buffer, @wire.int32_to_u64(v))
    @types.ScalarValue::Int64(v) =>
      @wire.write_uvarint(buffer, @wire.int64_to_u64(v))
    @types.ScalarValue::UInt32(v) =>
      @wire.write_uvarint(buffer, @wire.uint32_to_u64(v))
    @types.ScalarValue::UInt64(v) => @wire.write_uvarint(buffer, v)
    @types.ScalarValue::SInt32(v) =>
      @wire.write_uvarint(buffer, @wire.sint32_to_u64(v))
    @types.ScalarValue::SInt64(v) =>
      @wire.write_uvarint(buffer, @wire.sint64_to_u64(v))
    @types.ScalarValue::Bool(v) => {
      let payload = if v { 1UL } else { 0UL }
      @wire.write_uvarint(buffer, payload)
    }
    @types.ScalarValue::Enum(v) =>
      @wire.write_uvarint(buffer, @wire.int32_to_u64(v))
  }
}

///|
/// Write one scalar field: a tag followed by the scalar payload.
pub fn Encoder::write_scalar_field(
  self : Encoder,
  field_number : Int32,
  value : @types.ScalarValue,
) -> Unit raise @types.EncodeError {
  let tag = @wire.Tag::new(field_number, scalar_wire_type(value.scalar_type()))
  @wire.write_tag(self.buffer, tag)
  write_scalar_payload(self.buffer, value)
}

///|
/// Read one scalar payload according to `scalar_type`.
///
/// The tag has already been consumed by the caller. Use
/// `read_scalar_field` when the tag is still available and should be checked
/// against the expected wire type.
pub fn Decoder::read_scalar(
  self : Decoder,
  scalar_type : @types.ScalarType,
) -> @types.ScalarValue raise @types.DecodeError {
  read_scalar_from(self.reader, scalar_type)
}

///|
/// Read a scalar from an arbitrary reader window.
fn read_scalar_from(
  reader : @wire.WireReader,
  scalar_type : @types.ScalarType,
) -> @types.ScalarValue raise @types.DecodeError {
  match scalar_type {
    @types.ScalarType::Double =>
      @types.ScalarValue::Double(reader.read_double())
    @types.ScalarType::Float => @types.ScalarValue::Float(reader.read_float())
    @types.ScalarType::Fixed32 =>
      @types.ScalarValue::Fixed32(reader.read_fixed32())
    @types.ScalarType::SFixed32 =>
      @types.ScalarValue::SFixed32(reader.read_fixed32().reinterpret_as_int())
    @types.ScalarType::Fixed64 =>
      @types.ScalarValue::Fixed64(reader.read_fixed64())
    @types.ScalarType::SFixed64 =>
      @types.ScalarValue::SFixed64(reader.read_fixed64().reinterpret_as_int64())
    @types.ScalarType::Int32 =>
      @types.ScalarValue::Int32(@wire.u64_to_int32(reader.read_varint()))
    @types.ScalarType::Int64 =>
      @types.ScalarValue::Int64(@wire.u64_to_int64(reader.read_varint()))
    @types.ScalarType::UInt32 =>
      @types.ScalarValue::UInt32(@wire.u64_to_uint32(reader.read_varint()))
    @types.ScalarType::UInt64 =>
      @types.ScalarValue::UInt64(reader.read_varint())
    @types.ScalarType::SInt32 =>
      @types.ScalarValue::SInt32(@wire.u64_to_sint32(reader.read_varint()))
    @types.ScalarType::SInt64 =>
      @types.ScalarValue::SInt64(@wire.u64_to_sint64(reader.read_varint()))
    @types.ScalarType::Bool =>
      @types.ScalarValue::Bool(reader.read_varint() != 0UL)
    @types.ScalarType::Enum =>
      @types.ScalarValue::Enum(@wire.u64_to_int32(reader.read_varint()))
  }
}

///|
/// Check that `tag` uses the wire type required by `scalar_type`, then read the
/// scalar payload.
pub fn Decoder::read_scalar_field(
  self : Decoder,
  tag : @wire.Tag,
  scalar_type : @types.ScalarType,
) -> @types.ScalarValue raise @types.DecodeError {
  let expected = scalar_wire_type(scalar_type)
  if tag.wire_type() != expected {
    raise @types.UnexpectedWireType(
      offset=self.reader.position(),
      expected=expected.to_int(),
      actual=tag.wire_type().to_int(),
    )
  }
  self.read_scalar(scalar_type)
}
