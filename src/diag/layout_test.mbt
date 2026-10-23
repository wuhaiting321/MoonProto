// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
test "inspect reports offsets and varint values" {
  let fields = inspect(b"\x08\x96\x01")
  assert_eq(fields.length(), 1)
  assert_eq(fields[0].field_number, 1)
  assert_eq(fields[0].wire_type, @wire.WireType::Varint)
  assert_eq(fields[0].tag_offset, 0)
  assert_eq(fields[0].payload_offset, 1)
  assert_eq(fields[0].payload_length, 2)
  assert_eq(fields[0].preview, "150")
}

///|
test "inspect finds nested fields with absolute offsets" {
  let bytes = b"\x12\x08\x0A\x04leaf\x10\x0D"
  let fields = inspect(bytes)
  assert_eq(fields.length(), 1)
  assert_eq(fields[0].field_number, 2)
  assert_eq(fields[0].payload_length, 8)
  assert_eq(fields[0].children.length(), 2)
  let text = fields[0].children[0]
  assert_eq(text.field_number, 1)
  assert_eq(text.tag_offset, 2)
  assert_eq(text.payload_offset, 4)
  assert_eq(text.payload_length, 4)
  assert_eq(text.preview, "6c 65 61 66")
  let number = fields[0].children[1]
  assert_eq(number.field_number, 2)
  assert_eq(number.tag_offset, 8)
  assert_eq(number.payload_offset, 9)
  assert_eq(number.preview, "13")
}

///|
test "inspect renders fixed-width payloads in wire order" {
  let fields = inspect(b"\x0D\x78\x56\x34\x12")
  assert_eq(fields.length(), 1)
  assert_eq(fields[0].wire_type, @wire.WireType::Fixed32)
  assert_eq(fields[0].payload_length, 4)
  assert_eq(fields[0].preview, "12 34 56 78")
}

///|
test "inspect ignores length-delimited blobs that are not messages" {
  let fields = inspect(b"\x0A\x05hello")
  assert_eq(fields.length(), 1)
  assert_eq(fields[0].children.length(), 0)
}

///|
test "inspect enforces the field budget" {
  let options : InspectOptions = {
    max_fields: 1,
    max_depth: 32,
    preview_bytes: 16,
  }
  assert_true(
    try {
      let _ = inspect(b"\x08\x01\x10\x02", options~)
      false
    } catch {
      @types.FieldLimitExceeded(offset~, limit~) => offset == 2 && limit == 1
      _ => false
    },
  )
}

///|
test "inspect stops guessing children at the depth limit" {
  let options : InspectOptions = {
    max_fields: 4096,
    max_depth: 1,
    preview_bytes: 16,
  }
  let fields = inspect(b"\x0A\x04\x0A\x02\x08\x07", options~)
  assert_eq(fields[0].children.length(), 1)
  assert_eq(fields[0].children[0].children.length(), 0)
}

///|
test "inspect rejects unterminated groups" {
  assert_true(
    try {
      let _ = inspect(b"\x0B\x08\x01")
      false
    } catch {
      @types.UnterminatedGroup(..) => true
      _ => false
    },
  )
}

///|
test "render pins every field to its absolute offsets" {
  let fields = inspect(b"\x08\x96\x01")
  assert_eq(render(fields), "field 1 varint tag@0 payload@1 len=2 150")
}

///|
test "error context points at the failing byte" {
  let error = try {
    let _ = inspect(b"\x08\x80")
    panic()
  } catch {
    error => error
  }
  assert_eq(error_offset(error), Some(1))
  let context = error_context(b"\x08\x80", error)
  assert_eq(
    context,
    "truncated input at offset 1: needed 1 bytes, 0 available\n" +
    "  offset 1 of 2\n" +
    "   08 80\n" +
    "      ^^",
  )
}

///|
test "tag errors now carry the tag offset" {
  let offset = try {
    let _ = @wire.read_tag(b"\x0E", 0)
    -1
  } catch {
    error =>
      match error_offset(error) {
        Some(offset) => offset
        None => -1
      }
  }
  assert_eq(offset, 0)
}
