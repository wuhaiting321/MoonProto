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
/// Encode a chat message with a nested body and one field that only newer
/// clients send:
///
///   1: string sender
///   2: uint32 sent_at
///   3: message body
///        1: string text
///        2: bytes attachment
///   9: string client_hint (unknown to the old parser)
fn encode_message() -> Bytes raise {
  let body = @codec.Encoder::new()
  body.write_string(1, "hello from MoonProto")
  body.write_bytes(2, b"\x89\x50\x4e\x47")
  let message = @codec.Encoder::new()
  message.write_string(1, "alice")
  message.write_scalar_field(2, @types.ScalarValue::UInt32(1730000000U))
  message.write_message(3, body)
  message.write_string(9, "sent-from-v2")
  message.finish()
}

///|
/// Decode with the field map known to the old server. Unknown field 9 is
/// skipped, so adding fields to the producer stays backward compatible.
fn run() -> Unit raise {
  let bytes = encode_message()
  println(
    "chat message " + bytes.length().to_string() + " bytes: " + hex(bytes),
  )
  let mut sender = ""
  let mut sent_at : UInt32 = 0U
  let mut text = ""
  let mut attachment : Bytes = b""
  let mut skipped = 0
  let decoder = @codec.Decoder::new(bytes)
  while !decoder.is_empty() {
    let tag = decoder.next_tag().unwrap()
    match tag.field_number() {
      1 => sender = decoder.read_string()
      2 =>
        sent_at = match
          decoder.read_scalar_field(tag, @types.ScalarType::UInt32) {
          @types.ScalarValue::UInt32(value) => value
          _ => 0U
        }
      3 => {
        let body = decoder.read_submessage(tag)
        while !body.is_empty() {
          let body_tag = body.next_tag().unwrap()
          match body_tag.field_number() {
            1 => text = body.read_string()
            2 => attachment = body.read_bytes()
            _ => body.skip_tag(body_tag)
          }
        }
      }
      _ => {
        decoder.skip_tag(tag)
        skipped = skipped + 1
      }
    }
  }
  println("sender=" + sender + " sent_at=" + sent_at.to_string())
  println("text=" + text)
  println(
    "attachment=" +
    attachment.length().to_string() +
    " bytes: " +
    hex(attachment),
  )
  println(
    "skipped " + skipped.to_string() + " unknown field(s), message still parsed",
  )
}

///|
fn main {
  run() catch {
    error => println("example failed: " + error.to_string())
  }
}
