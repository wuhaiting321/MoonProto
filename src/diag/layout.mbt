// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// One field discovered by schema-free wire inspection.
///
/// Offsets are absolute positions in the original byte array, so a field found
/// inside an embedded message still points at the exact byte a hex editor
/// would show. `preview` is a short, human-readable rendering of the payload:
/// a decimal value for varints, a truncated hexadecimal dump otherwise.
pub(all) struct WireField {
  field_number : Int32
  wire_type : @wire.WireType
  tag_offset : Int32
  payload_offset : Int32
  payload_length : Int32
  preview : String
  children : Array[WireField]
}

///|
/// Limits applied while inspecting untrusted bytes.
///
/// `max_fields` caps the total number of fields recorded across all nesting
/// levels, including fields discovered in speculative nested parses.
/// `max_depth` stops recursive layout guessing. `preview_bytes` bounds the
/// hexadecimal preview of a length-delimited payload.
pub(all) struct InspectOptions {
  max_fields : Int32
  max_depth : Int32
  preview_bytes : Int32
}

///|
/// Conservative defaults for diagnostics on untrusted input.
pub fn InspectOptions::default() -> InspectOptions {
  { max_fields: 4096, max_depth: 32, preview_bytes: 16, }
}

///|
/// Mutable counter shared by recursive layout passes.
priv struct InspectState {
  options : InspectOptions
  mut recorded : Int32
}

///|
/// Walk protobuf wire bytes without a schema and return the field layout.
///
/// The function records the field number, wire type, tag offset, payload
/// offset, payload length, and a short preview for every field. A
/// length-delimited payload is also parsed as an embedded message when it
/// happens to form a complete, well-formed field sequence; this is a heuristic
/// similar to `protoc --decode_raw`, so `children` may be empty for binary
/// blobs and should be treated as a hint rather than a schema.
///
/// Raises `DecodeError` for malformed input and `FieldLimitExceeded` when the
/// field budget is exhausted, so a hostile payload cannot make the inspector
/// allocate without bound.
pub fn inspect(
  bytes : Bytes,
  options~ : InspectOptions = InspectOptions::default(),
) -> Array[WireField] raise @types.DecodeError {
  let state : InspectState = { options, recorded: 0, }
  inspect_window(bytes, @wire.WireReader::new(bytes), 0, state)
}

///|
/// Inspect every field in `reader`'s window.
fn inspect_window(
  bytes : Bytes,
  reader : @wire.WireReader,
  depth : Int32,
  state : InspectState,
) -> Array[WireField] raise @types.DecodeError {
  let fields : Array[WireField] = []
  while !reader.is_empty() {
    if state.recorded >= state.options.max_fields {
      raise @types.FieldLimitExceeded(
        offset=reader.position(),
        limit=state.options.max_fields,
      )
    }
    fields.push(inspect_field(bytes, reader, depth, state))
  }
  fields
}

///|
/// Record one field and advance the reader past its payload.
fn inspect_field(
  bytes : Bytes,
  reader : @wire.WireReader,
  depth : Int32,
  state : InspectState,
) -> WireField raise @types.DecodeError {
  let tag_offset = reader.position()
  let tag = reader.next_tag()
  let mut payload_offset = reader.position()
  let mut payload_length = 0
  let mut preview = ""
  let mut children : Array[WireField] = []
  match tag.wire_type() {
    @wire.WireType::Varint => {
      let value = reader.read_varint()
      payload_length = reader.position() - payload_offset
      preview = value.to_string()
    }
    @wire.WireType::Fixed64 => {
      let value = reader.read_fixed64()
      payload_length = 8
      preview = fixed_preview(value, 8)
    }
    @wire.WireType::Fixed32 => {
      let value = reader.read_fixed32()
      payload_length = 4
      preview = fixed_preview(value.to_uint64(), 4)
    }
    @wire.WireType::LengthDelimited => {
      payload_length = reader.read_length()
      payload_offset = reader.position()
      let start = payload_offset
      preview = hex_preview(
        bytes,
        start,
        payload_length,
        state.options.preview_bytes,
      )
      if depth < state.options.max_depth {
        children = guess_children(bytes, start, payload_length, depth, state)
      }
      reader.skip(payload_length)
    }
    @wire.WireType::StartGroup => {
      reader.skip_tag(tag)
      payload_length = reader.position() - payload_offset
      preview = "group"
    }
    @wire.WireType::EndGroup =>
      raise @types.UnexpectedEndGroup(offset=reader.position())
  }
  state.recorded = state.recorded + 1
  {
    field_number: tag.field_number(),
    wire_type: tag.wire_type(),
    tag_offset,
    payload_offset,
    payload_length,
    preview,
    children,
  }
}

///|
/// Try to parse a length-delimited payload as an embedded message.
///
/// A parse that fails, or that records no field, is rolled back so the global
/// field budget only counts layouts that are actually reported.
fn guess_children(
  bytes : Bytes,
  start : Int32,
  length : Int32,
  depth : Int32,
  state : InspectState,
) -> Array[WireField] {
  if length <= 0 {
    return []
  }
  let before = state.recorded
  try {
    let reader = @wire.WireReader::new_limited(bytes, start, start + length)
    let fields = inspect_window(bytes, reader, depth + 1, state)
    if fields.is_empty() {
      state.recorded = before
      []
    } else {
      fields
    }
  } catch {
    _ => {
      state.recorded = before
      []
    }
  }
}

///|
/// Render a bounded hexadecimal preview of `length` bytes at `start`.
fn hex_preview(
  bytes : Bytes,
  start : Int32,
  length : Int32,
  limit : Int32,
) -> String {
  if length <= 0 {
    return "empty"
  }
  let shown = if length < limit { length } else { limit }
  let mut text = ""
  for index in 0..<shown {
    if index > 0 {
      text = text + " "
    }
    text = text + bytes[start + index].to_hex()
  }
  if length > shown {
    text = text + " ..."
  }
  text
}

///|
/// Render `width` low bytes of `value` most-significant byte first.
fn fixed_preview(value : UInt64, width : Int32) -> String {
  let mut text = ""
  for index in 0..<width {
    if index > 0 {
      text = text + " "
    }
    let shift = (width - 1 - index) * 8
    let byte = ((value >> shift) & 0xFFUL).to_byte()
    text = text + byte.to_hex()
  }
  text
}

///|
/// Human-readable wire type name used by the text report.
fn wire_type_name(wire_type : @wire.WireType) -> String {
  match wire_type {
    @wire.WireType::Varint => "varint"
    @wire.WireType::Fixed64 => "fixed64"
    @wire.WireType::LengthDelimited => "length-delimited"
    @wire.WireType::StartGroup => "start-group"
    @wire.WireType::EndGroup => "end-group"
    @wire.WireType::Fixed32 => "fixed32"
  }
}

///|
/// Render an inspected layout as an indented text tree.
///
/// Each line carries the absolute tag and payload offsets, which lets a reader
/// jump from a report line straight to the same byte in a hex dump.
pub fn render(fields : Array[WireField]) -> String {
  render_into(fields, 0, "")
}

///|
/// Append rendered `fields` to `text` with the given indentation level.
fn render_into(
  fields : Array[WireField],
  depth : Int32,
  text : String,
) -> String {
  let mut result = text
  let mut indent = ""
  for _ in 0..<depth {
    indent = indent + "  "
  }
  for field in fields {
    if result.length() > 0 {
      result = result + "\n"
    }
    result = result +
      indent +
      "field " +
      field.field_number.to_string() +
      " " +
      wire_type_name(field.wire_type) +
      " tag@" +
      field.tag_offset.to_string() +
      " payload@" +
      field.payload_offset.to_string() +
      " len=" +
      field.payload_length.to_string() +
      " " +
      field.preview
    result = render_into(field.children, depth + 1, result)
  }
  result
}
