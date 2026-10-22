// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
test "wire types use the defined three-bit values" {
  let cases : Array[(WireType, Int32)] = [
    (WireType::Varint, 0),
    (WireType::Fixed64, 1),
    (WireType::LengthDelimited, 2),
    (WireType::StartGroup, 3),
    (WireType::EndGroup, 4),
    (WireType::Fixed32, 5),
  ]
  for case in cases {
    assert_eq(case.0.to_int(), case.1)
    assert_eq(WireType::from_int(case.1), case.0)
  }
}

///|
test "wire types 6 and 7 are rejected" {
  for value in [6, 7] {
    assert_true(
      try {
        let _ = WireType::from_int(value)
        false
      } catch {
        @types.UnknownWireType(_) => true
        _ => false
      },
    )
  }
}

///|
test "only scalar wire types are packable" {
  assert_true(WireType::Varint.is_packable())
  assert_true(WireType::Fixed64.is_packable())
  assert_true(WireType::Fixed32.is_packable())
  assert_false(WireType::LengthDelimited.is_packable())
  assert_false(WireType::StartGroup.is_packable())
  assert_false(WireType::EndGroup.is_packable())
}

///|
test "field number range includes the reserved implementation band" {
  assert_false(is_field_number_in_range(0))
  assert_true(is_field_number_in_range(1))
  assert_true(is_field_number_in_range(18999))
  assert_true(is_field_number_in_range(19000))
  assert_true(is_field_number_in_range(19999))
  assert_true(is_field_number_in_range(20000))
  assert_true(is_field_number_in_range(536870911))
  assert_false(is_field_number_in_range(536870912))
  assert_false(is_reserved_field_number(18999))
  assert_true(is_reserved_field_number(19000))
  assert_true(is_reserved_field_number(19999))
  assert_false(is_reserved_field_number(20000))
}

///|
test "Tag::new rejects out-of-range field numbers" {
  for number in [0, -1, 536870912] {
    assert_true(
      try {
        let _ = Tag::new(number, WireType::Varint)
        false
      } catch {
        @types.FieldNumberOutOfRange(_) => true
        _ => false
      },
    )
  }
}

///|
test "Tag::new rejects implementation-reserved field numbers" {
  for number in [19000, 19500, 19999] {
    assert_true(
      try {
        let _ = Tag::new(number, WireType::LengthDelimited)
        false
      } catch {
        @types.ReservedFieldNumber(_) => true
        _ => false
      },
    )
  }
  let tag = Tag::new(20000, WireType::LengthDelimited)
  assert_eq(tag.field_number(), 20000)
  assert_eq(tag.wire_type(), WireType::LengthDelimited)
}

///|
test "tags encode as field_number shifted left three bits" {
  let cases : Array[(Int32, WireType, Bytes)] = [
    (1, WireType::Varint, b"\x08"),
    (2, WireType::LengthDelimited, b"\x12"),
    (15, WireType::LengthDelimited, b"\x7A"),
    (16, WireType::Varint, b"\x80\x01"),
    (1, WireType::Fixed64, b"\x09"),
    (1, WireType::StartGroup, b"\x0B"),
    (1, WireType::EndGroup, b"\x0C"),
    (1, WireType::Fixed32, b"\x0D"),
    (536870911, WireType::Fixed32, b"\xFD\xFF\xFF\xFF\x0F"),
  ]
  for case in cases {
    let tag = Tag::new(case.0, case.1)
    assert_eq(tag.encode(), case.2)
    assert_eq(tag.encoded_len(), case.2.length())
  }
}

///|
test "tag writes append to an existing buffer" {
  let buffer = @buffer.Buffer()
  write_tag(buffer, Tag::new(1, WireType::Varint))
  write_tag(buffer, Tag::new(16, WireType::LengthDelimited))
  assert_eq(buffer.to_bytes(), b"\x08\x82\x01")
}

///|
test "tags round-trip across field-number and wire-type boundaries" {
  let fields : Array[Int32] = [1, 2, 15, 16, 2047, 2048, 536870911]
  let wire_types : Array[WireType] = [
    WireType::Varint,
    WireType::Fixed64,
    WireType::LengthDelimited,
    WireType::StartGroup,
    WireType::EndGroup,
    WireType::Fixed32,
  ]
  for field in fields {
    for wire_type in wire_types {
      let encoded = Tag::new(field, wire_type).encode()
      let (decoded, next) = read_tag(encoded, 0)
      assert_eq(decoded.field_number(), field)
      assert_eq(decoded.wire_type(), wire_type)
      assert_eq(next, encoded.length())
    }
  }
}

///|
test "read_tag reports offsets after a prefix" {
  let bytes = b"\xAA\x08\x01"
  let (tag, next) = read_tag(bytes, 1)
  assert_eq(tag.field_number(), 1)
  assert_eq(tag.wire_type(), WireType::Varint)
  assert_eq(next, 2)
}

///|
test "read_tag rejects field number zero" {
  assert_true(
    try {
      let _ = read_tag(b"\x00", 0)
      false
    } catch {
      @types.InvalidFieldNumber(field_number~) => field_number == 0
      _ => false
    },
  )
}

///|
test "read_tag rejects unknown wire types 6 and 7" {
  for bytes in [b"\x0E", b"\x0F"] {
    assert_true(
      try {
        let _ = read_tag(bytes, 0)
        false
      } catch {
        @types.UnknownWireType(_) => true
        _ => false
      },
    )
  }
}

///|
test "read_tag rejects field numbers above 2^29 - 1" {
  let encoded = encode_uvarint(0x100000000UL)
  assert_true(
    try {
      let _ = read_tag(encoded, 0)
      false
    } catch {
      @types.TagValueOutOfRange(_) => true
      _ => false
    },
  )
}

///|
test "read_tag rejects truncated tag varints" {
  assert_true(
    try {
      let _ = read_tag(b"\x80", 0)
      false
    } catch {
      @types.Truncated(..) => true
      _ => false
    },
  )
}

///|
test "read_tag accepts reserved implementation field numbers" {
  let encoded = encode_uvarint((19000UL << 3) | 2UL)
  let (tag, next) = read_tag(encoded, 0)
  assert_eq(tag.field_number(), 19000)
  assert_eq(tag.wire_type(), WireType::LengthDelimited)
  assert_eq(next, encoded.length())
}
