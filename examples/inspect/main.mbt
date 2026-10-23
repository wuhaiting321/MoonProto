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
/// A captured vendor packet with no `.proto` file and no generated code.
/// The layout is recovered purely from the wire bytes:
///
///   1: varint 1
///   2: embedded message
///        1: string "leaf"
///        2: varint 13
///   3: fixed32 0x12345678
///   9: string "v2"
fn captured_packet() -> Bytes {
  b"\x08\x01\x12\x08\x0A\x04leaf\x10\x0D\x1D\x78\x56\x34\x12\x4A\x02v2"
}

///|
/// Inspect a packet whose schema is unknown, then show how a truncated packet
/// is reported. Both operations work without a `.proto` parser or codec
/// generation.
fn run() -> Unit raise {
  let bytes = captured_packet()
  println(
    "captured packet " + bytes.length().to_string() + " bytes: " + hex(bytes),
  )
  println("layout:")
  println(@diag.render(@diag.inspect(bytes)))
  let broken = b"\x08\x96\x01\x12\x05ab"
  try {
    let _ = @diag.inspect(broken)
    println("malformed packet was accepted")
  } catch {
    error => {
      println("malformed packet rejected:")
      println(@diag.error_context(broken, error))
    }
  }
}

///|
fn main {
  run() catch {
    error => println("example failed: " + error.to_string())
  }
}
