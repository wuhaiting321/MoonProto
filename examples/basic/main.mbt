// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Render wire bytes as space-separated hexadecimal pairs.
fn hex(bytes : Bytes) -> String {
  let mut text = ""
  for index in 0..<bytes.length() {
    if index > 0 {
      text = text + " "
    }
    text = text + bytes[index].to_hex()
  }
  text
}

///|
/// Render the scalar values used by this example.
fn scalar_text(value : @types.ScalarValue) -> String {
  match value {
    @types.ScalarValue::UInt32(v) => v.to_string()
    @types.ScalarValue::SInt32(v) => v.to_string()
    @types.ScalarValue::Int32(v) => v.to_string()
    @types.ScalarValue::UInt64(v) => v.to_string()
    @types.ScalarValue::Bool(v) => if v { "true" } else { "false" }
    _ => "?"
  }
}

///|
/// Encode a message tree, decode it again, and show how malformed input is
/// reported.
///
/// Build:
///   1: uint32 150
///   2: child
///        1: string "leaf"
///        2: sint32 -7
fn run() -> Unit raise {
  let leaf = @codec.Encoder::new()
  leaf.write_string(1, "leaf")
  leaf.write_scalar_field(2, @types.ScalarValue::SInt32(-7))
  let root = @codec.Encoder::new()
  root.write_scalar_field(1, @types.ScalarValue::UInt32(150U))
  root.write_message(2, leaf)
  let bytes = root.finish()
  println("encoded " + bytes.length().to_string() + " bytes: " + hex(bytes))
  let decoder = @codec.Decoder::new(bytes)
  while !decoder.is_empty() {
    let tag = match decoder.next_tag() {
      Some(tag) => tag
      None => break
    }
    match tag.field_number() {
      1 => {
        let value = decoder.read_scalar_field(tag, @types.ScalarType::UInt32)
        println("field 1 uint32 = " + scalar_text(value))
      }
      2 => {
        let child = decoder.read_submessage(tag)
        println("field 2 message depth = " + child.depth().to_string())
        while !child.is_empty() {
          let child_tag = match child.next_tag() {
            Some(tag) => tag
            None => break
          }
          match child_tag.field_number() {
            1 => println("  field 1 string = " + child.read_string())
            2 => {
              let value = child.read_scalar_field(
                child_tag,
                @types.ScalarType::SInt32,
              )
              println("  field 2 sint32 = " + scalar_text(value))
            }
            _ => child.skip_tag(child_tag)
          }
        }
      }
      _ => decoder.skip_tag(tag)
    }
  }
  let broken = @codec.Decoder::new(b"\x08\x80")
  match broken.next_tag() {
    Some(tag) =>
      try {
        let _ = broken.read_scalar_field(tag, @types.ScalarType::UInt64)
        println("malformed input was accepted")
      } catch {
        error => println("malformed input rejected: " + error.message())
      }
    None => println("unexpected empty input")
  }
}

///|
fn main {
  run() catch {
    error => println("example failed: " + error.to_string())
  }
}
