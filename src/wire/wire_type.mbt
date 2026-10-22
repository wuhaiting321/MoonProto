// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// The six wire types defined by the Protocol Buffers encoding specification.
///
/// A tag encodes a three-bit wire type next to a 29-bit field number. Wire
/// types 0, 1, 2, and 5 carry scalar payloads; types 3 and 4 delimit groups,
/// which are accepted for forward compatibility but are not produced by
/// proto3 schemas.
pub(all) enum WireType {
  /// Base-128 varint: `int32`, `int64`, `uint32`, `uint64`, `sint32`,
  /// `sint64`, `bool`, and `enum`.
  Varint
  /// Eight little-endian bytes: `fixed64`, `sfixed64`, and `double`.
  Fixed64
  /// A varint length followed by that many bytes: strings, bytes, embedded
  /// messages, and packed repeated fields.
  LengthDelimited
  /// Opens a deprecated group; no length prefix is present.
  StartGroup
  /// Closes a deprecated group.
  EndGroup
  /// Four little-endian bytes: `fixed32`, `sfixed32`, and `float`.
  Fixed32
} derive(Debug, Eq)

///|
/// Explicit trait-method promotion for the derived `Debug` implementation.
pub extend WireType with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Explicit trait-method promotion for the derived `Eq` implementation.
pub extend WireType with Eq::{equal, not_equal}

///|
/// Smallest valid protobuf field number.
pub const MIN_FIELD_NUMBER : Int32 = 1

///|
/// Largest valid protobuf field number (`2^29 - 1`).
pub const MAX_FIELD_NUMBER : Int32 = 536870911

///|
/// First field number reserved for protobuf implementations.
pub const FIRST_RESERVED_FIELD_NUMBER : Int32 = 19000

///|
/// Last field number reserved for protobuf implementations.
pub const LAST_RESERVED_FIELD_NUMBER : Int32 = 19999

///|
/// Maximum group nesting accepted while skipping unknown fields.
pub const MAX_GROUP_DEPTH : Int32 = 100

///|
/// Convert a wire type to its three-bit tag value.
pub fn WireType::to_int(self : WireType) -> Int32 {
  match self {
    Varint => 0
    Fixed64 => 1
    LengthDelimited => 2
    StartGroup => 3
    EndGroup => 4
    Fixed32 => 5
  }
}

///|
/// Convert a three-bit tag value to a wire type.
///
/// Raises `DecodeError` for the two unused bit patterns 6 and 7.
pub fn WireType::from_int(value : Int32) -> WireType raise @types.DecodeError {
  match value {
    0 => Varint
    1 => Fixed64
    2 => LengthDelimited
    3 => StartGroup
    4 => EndGroup
    5 => Fixed32
    _ => raise @types.UnknownWireType(value~)
  }
}

///|
/// Report whether a wire type carries a payload that can be repeated in a
/// packed length-delimited field.
pub fn WireType::is_packable(self : WireType) -> Bool {
  match self {
    Varint | Fixed64 | Fixed32 => true
    LengthDelimited | StartGroup | EndGroup => false
  }
}

///|
/// Check that `number` lies in the range allowed by the wire format.
///
/// Reserved implementation numbers 19000..19999 remain decodable so that
/// unknown fields from other producers are not rejected.
pub fn is_field_number_in_range(number : Int32) -> Bool {
  number >= MIN_FIELD_NUMBER && number <= MAX_FIELD_NUMBER
}

///|
/// Check whether `number` is reserved for protobuf implementations.
pub fn is_reserved_field_number(number : Int32) -> Bool {
  number >= FIRST_RESERVED_FIELD_NUMBER && number <= LAST_RESERVED_FIELD_NUMBER
}

///|
/// A decoded protobuf tag: a field number paired with a wire type.
pub struct Tag {
  field_number : Int32
  wire_type : WireType
} derive(Debug, Eq)

///|
/// Explicit trait-method promotion for the derived `Debug` implementation.
pub extend Tag with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Explicit trait-method promotion for the derived `Eq` implementation.
pub extend Tag with Eq::{equal, not_equal}

///|
/// The field number carried by a tag.
pub fn Tag::field_number(self : Tag) -> Int32 {
  self.field_number
}

///|
/// The wire type carried by a tag.
pub fn Tag::wire_type(self : Tag) -> WireType {
  self.wire_type
}

///|
/// Build a tag for encoding.
///
/// Raises `EncodeError` when the field number is outside the protobuf range or
/// falls inside the implementation-reserved range.
pub fn Tag::new(
  field_number : Int32,
  wire_type : WireType,
) -> Tag raise @types.EncodeError {
  if !is_field_number_in_range(field_number) {
    raise @types.FieldNumberOutOfRange(field_number~)
  }
  if is_reserved_field_number(field_number) {
    raise @types.ReservedFieldNumber(field_number~)
  }
  { field_number, wire_type, }
}

///|
/// Encode a tag as the unsigned varint of `field_number << 3 | wire_type`.
pub fn Tag::encode(self : Tag) -> Bytes {
  let raw = tag_value(self.field_number, self.wire_type.to_int())
  encode_uvarint(raw)
}

///|
/// Number of varint bytes needed to encode a tag.
pub fn Tag::encoded_len(self : Tag) -> Int32 {
  uvarint_len(tag_value(self.field_number, self.wire_type.to_int()))
}

///|
/// Append an encoded tag to `buffer`.
pub fn write_tag(buffer : @buffer.Buffer, tag : Tag) -> Unit {
  write_uvarint(buffer, tag_value(tag.field_number, tag.wire_type.to_int()))
}

///|
/// Compute the raw 32-bit tag value for a field number and wire type.
fn tag_value(field_number : Int32, wire_type : Int32) -> UInt64 {
  (field_number.to_uint64() << 3) | wire_type.to_uint64()
}

///|
/// Decode one tag starting at `offset`.
///
/// Returns the tag and the offset of the first byte after the tag. Raises
/// `DecodeError` when the varint is malformed, the field number is zero or out
/// of range, or the wire type is 6 or 7.
pub fn read_tag(
  bytes : Bytes,
  offset : Int32,
) -> (Tag, Int32) raise @types.DecodeError {
  let (raw, next) = read_uvarint(bytes, offset)
  if raw > 0xFFFFFFFFUL {
    raise @types.TagValueOutOfRange(value=raw)
  }
  let field_number = (raw >> 3).to_uint().reinterpret_as_int()
  if !is_field_number_in_range(field_number) {
    raise @types.InvalidFieldNumber(field_number~)
  }
  let wire_value = (raw & 7UL).to_uint().reinterpret_as_int()
  let wire_type = WireType::from_int(wire_value)
  ({ field_number, wire_type, }, next)
}
