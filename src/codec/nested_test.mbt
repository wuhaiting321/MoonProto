// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Recursively descend through a chain of single embedded messages.
fn descend(decoder : Decoder) -> Unit raise @types.DecodeError {
  if !decoder.is_empty() {
    match decoder.next_tag() {
      Some(tag) => descend(decoder.read_submessage(tag))
      None => ()
    }
  }
}

///|
/// Build `levels` nested messages, each holding the previous one in field 1.
fn wrap(levels : Int32) -> Bytes raise @types.EncodeError {
  let mut message = Encoder::new()
  for _ in 0..<levels {
    let parent = Encoder::new()
    parent.write_message(1, message)
    message = parent
  }
  message.finish()
}

///|
test "embedded messages encode as length-delimited payloads" {
  let inner = Encoder::new()
  inner.write_string(1, "a")
  inner.write_scalar_field(2, @types.ScalarValue::UInt32(150U))
  let outer = Encoder::new()
  outer.write_message(3, inner)
  assert_eq(outer.finish(), b"\x1A\x06\x0A\x01a\x10\x96\x01")
}

///|
test "nested messages round-trip through recursive subdecoders" {
  let leaf = Encoder::new()
  leaf.write_string(1, "leaf")
  let middle = Encoder::new()
  middle.write_message(2, leaf)
  middle.write_scalar_field(3, @types.ScalarValue::UInt32(7U))
  let top = Encoder::new()
  top.write_message(4, middle)
  top.write_scalar_field(5, @types.ScalarValue::Bool(true))

  let top_decoder = Decoder::new(top.finish())
  assert_eq(top_decoder.depth(), 0)
  match top_decoder.next_tag() {
    Some(tag) => {
      assert_eq(tag.field_number(), 4)
      let middle_decoder = top_decoder.read_submessage(tag)
      assert_eq(middle_decoder.depth(), 1)
      match middle_decoder.next_tag() {
        Some(middle_tag) => {
          assert_eq(middle_tag.field_number(), 2)
          let leaf_decoder = middle_decoder.read_submessage(middle_tag)
          assert_eq(leaf_decoder.depth(), 2)
          match leaf_decoder.next_tag() {
            Some(_) => assert_eq(leaf_decoder.read_string(), "leaf")
            None => assert_true(false)
          }
          assert_true(leaf_decoder.is_empty())
        }
        None => assert_true(false)
      }
      match middle_decoder.next_tag() {
        Some(middle_tag) =>
          assert_eq(
            middle_decoder.read_scalar_field(
              middle_tag,
              @types.ScalarType::UInt32,
            ),
            @types.ScalarValue::UInt32(7U),
          )
        None => assert_true(false)
      }
      assert_true(middle_decoder.is_empty())
    }
    None => assert_true(false)
  }
  match top_decoder.next_tag() {
    Some(tag) =>
      assert_eq(
        top_decoder.read_scalar_field(tag, @types.ScalarType::Bool),
        @types.ScalarValue::Bool(true),
      )
    None => assert_true(false)
  }
  assert_true(top_decoder.is_empty())
}

///|
test "empty embedded messages are preserved as present fields" {
  let outer = Encoder::new()
  outer.write_message(1, Encoder::new())
  assert_eq(outer.finish(), b"\x0A\x00")
  let decoder = Decoder::new(b"\x0A\x00")
  match decoder.next_tag() {
    Some(tag) => {
      let child = decoder.read_submessage(tag)
      assert_true(child.is_empty())
      assert_eq(child.depth(), 1)
    }
    None => assert_true(false)
  }
  assert_true(decoder.is_empty())
}

///|
test "embedded messages can contain packed fields" {
  let inner = Encoder::new()
  inner.write_packed_scalar_field(1, [
    @types.ScalarValue::SInt32(-1),
    @types.ScalarValue::SInt32(1),
  ])
  let outer = Encoder::new()
  outer.write_message(2, inner)
  let decoder = Decoder::new(outer.finish())
  match decoder.next_tag() {
    Some(tag) => {
      let child = decoder.read_submessage(tag)
      match child.next_tag() {
        Some(packed_tag) =>
          assert_eq(
            child.read_packed_scalar_field(
              packed_tag,
              @types.ScalarType::SInt32,
            ),
            [@types.ScalarValue::SInt32(-1), @types.ScalarValue::SInt32(1)],
          )
        None => assert_true(false)
      }
      assert_true(child.is_empty())
    }
    None => assert_true(false)
  }
  assert_true(decoder.is_empty())
}

///|
test "embedded messages keep the parent message aligned" {
  let inner = Encoder::new()
  inner.write_string(1, "x")
  let outer = Encoder::new()
  outer.write_message(1, inner)
  outer.write_bytes(2, b"T")
  let decoder = Decoder::new(outer.finish())
  match decoder.next_tag() {
    Some(tag) => {
      let child = decoder.read_submessage(tag)
      match child.next_tag() {
        Some(_) => assert_eq(child.read_string(), "x")
        None => assert_true(false)
      }
      assert_true(child.is_empty())
    }
    None => assert_true(false)
  }
  match decoder.next_tag() {
    Some(tag) => {
      assert_eq(tag.field_number(), 2)
      assert_eq(decoder.read_bytes(), b"T")
    }
    None => assert_true(false)
  }
  assert_true(decoder.is_empty())
}

///|
test "read_submessage rejects non-length-delimited tags" {
  let decoder = Decoder::new(b"\x08\x01")
  match decoder.next_tag() {
    Some(tag) =>
      assert_true(
        try {
          let _ = decoder.read_submessage(tag)
          false
        } catch {
          @types.UnexpectedWireType(expected~, actual~, ..) =>
            expected == 2 && actual == 0
          _ => false
        },
      )
    None => assert_true(false)
  }
}

///|
test "read_submessage rejects truncated payloads" {
  for bytes in [b"\x0A", b"\x0A\x05\x0A"] {
    let decoder = Decoder::new(bytes)
    match decoder.next_tag() {
      Some(tag) =>
        assert_true(
          try {
            let _ = decoder.read_submessage(tag)
            false
          } catch {
            @types.Truncated(..) | @types.LengthOutOfBounds(..) => true
            _ => false
          },
        )
      None => assert_true(false)
    }
  }
}

///|
test "nested messages stop at the recursion limit" {
  descend(Decoder::new(wrap(100)))
  assert_true(
    try {
      descend(Decoder::new(wrap(101)))
      false
    } catch {
      @types.RecursionLimitExceeded(limit~) => limit == 100
      _ => false
    },
  )
}
