// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// A bounds-checked cursor over protobuf wire bytes.
///
/// A reader owns a window `[position, limit)` into a byte sequence. Embedded
/// messages use a child reader whose limit is the end of the declared length,
/// so a nested parser cannot read past its own message. The parent advances
/// past the whole length-delimited payload after handing out the child.
pub struct WireReader {
  bytes : Bytes
  mut position : Int
  limit : Int
}

///|
/// Create a reader over all of `bytes`.
pub fn WireReader::new(bytes : Bytes) -> WireReader {
  { bytes, position: 0, limit: bytes.length(), }
}

///|
/// Create a reader over the window `[start, end)` of `bytes`.
///
/// Raises `DecodeError` when the window is negative or outside the input.
pub fn WireReader::new_limited(
  bytes : Bytes,
  start : Int,
  end : Int,
) -> WireReader raise @types.DecodeError {
  if start < 0 || end < start || end > bytes.length() {
    raise @types.Truncated(
      offset=start,
      needed=end - start,
      available=bytes.length(),
    )
  }
  { bytes, position: start, limit: end, }
}

///|
/// Current read offset, measured from the start of the underlying byte array.
pub fn WireReader::position(self : WireReader) -> Int {
  self.position
}

///|
/// Number of bytes left in this reader's window.
pub fn WireReader::remaining(self : WireReader) -> Int {
  if self.position >= self.limit {
    0
  } else {
    self.limit - self.position
  }
}

///|
/// Whether the reader has consumed its whole window.
pub fn WireReader::is_empty(self : WireReader) -> Bool {
  self.remaining() == 0
}

///|
/// Ensure that `count` bytes are available.
fn WireReader::ensure(
  self : WireReader,
  count : Int,
) -> Unit raise @types.DecodeError {
  let available = self.remaining()
  if count < 0 || count > available {
    raise @types.Truncated(offset=self.position, needed=count, available~)
  }
}

///|
/// Read one raw byte.
pub fn WireReader::read_byte(
  self : WireReader,
) -> Byte raise @types.DecodeError {
  self.ensure(1)
  let byte = self.bytes[self.position]
  self.position = self.position + 1
  byte
}

///|
/// Read one unsigned varint and advance past it.
pub fn WireReader::read_varint(
  self : WireReader,
) -> UInt64 raise @types.DecodeError {
  let (value, next) = read_uvarint(self.bytes, self.position)
  if next > self.limit {
    raise @types.Truncated(
      offset=self.position,
      needed=next - self.position,
      available=self.remaining(),
    )
  }
  self.position = next
  value
}

///|
/// Read one little-endian `fixed32` payload.
pub fn WireReader::read_fixed32(
  self : WireReader,
) -> UInt raise @types.DecodeError {
  self.ensure(4)
  let base = self.position
  let value = self.bytes[base].to_uint() |
    (self.bytes[base + 1].to_uint() << 8) |
    (self.bytes[base + 2].to_uint() << 16) |
    (self.bytes[base + 3].to_uint() << 24)
  self.position = base + 4
  value
}

///|
/// Read one little-endian `fixed64` payload.
pub fn WireReader::read_fixed64(
  self : WireReader,
) -> UInt64 raise @types.DecodeError {
  self.ensure(8)
  let base = self.position
  let mut value = 0UL
  for index in 0..<8 {
    value = value | (self.bytes[base + index].to_uint64() << (index * 8))
  }
  self.position = base + 8
  value
}

///|
/// Read one little-endian IEEE-754 `float`.
pub fn WireReader::read_float(
  self : WireReader,
) -> Float raise @types.DecodeError {
  Float::reinterpret_from_uint(self.read_fixed32())
}

///|
/// Read one little-endian IEEE-754 `double`.
pub fn WireReader::read_double(
  self : WireReader,
) -> Double raise @types.DecodeError {
  self.read_fixed64().reinterpret_as_double()
}

///|
/// Read a length prefix without consuming the payload that follows it.
///
/// The declared length is validated against the bytes left in this reader's
/// window. Returns the payload length; the cursor is left on the first payload
/// byte.
pub fn WireReader::read_length(
  self : WireReader,
) -> Int raise @types.DecodeError {
  let length_offset = self.position
  let (raw, next) = read_uvarint(self.bytes, self.position)
  if next > self.limit {
    raise @types.Truncated(
      offset=length_offset,
      needed=next - length_offset,
      available=self.remaining(),
    )
  }
  let remaining = self.limit - next
  if raw > remaining.to_uint64() {
    raise @types.LengthOutOfBounds(offset=length_offset, length=raw, remaining~)
  }
  self.position = next
  raw.to_uint().reinterpret_as_int()
}

///|
/// Read `length` raw bytes as an owned copy.
pub fn WireReader::read_bytes(
  self : WireReader,
  length : Int,
) -> Bytes raise @types.DecodeError {
  let available = self.remaining()
  if length < 0 || length > available {
    raise @types.LengthOutOfBounds(
      offset=self.position,
      length=length.to_uint64(),
      remaining=available,
    )
  }
  let start = self.position
  self.position = start + length
  self.bytes[start:start + length].to_owned()
}

///|
/// Consume a length-delimited payload and return a reader limited to it.
///
/// The returned child reader shares the underlying bytes. The parent is moved
/// past the payload, so callers can continue parsing the enclosing message
/// while the child parses the embedded one.
pub fn WireReader::read_subreader(
  self : WireReader,
) -> WireReader raise @types.DecodeError {
  let length = self.read_length()
  let start = self.position
  self.position = start + length
  { bytes: self.bytes, position: start, limit: start + length, }
}

///|
/// Read one tag and advance past it.
pub fn WireReader::next_tag(self : WireReader) -> Tag raise @types.DecodeError {
  let (tag, next) = read_tag(self.bytes, self.position)
  if next > self.limit {
    raise @types.Truncated(
      offset=self.position,
      needed=next - self.position,
      available=self.remaining(),
    )
  }
  self.position = next
  tag
}

///|
/// Skip `count` bytes inside the current window.
pub fn WireReader::skip(
  self : WireReader,
  count : Int,
) -> Unit raise @types.DecodeError {
  self.ensure(count)
  self.position = self.position + count
}

///|
/// Skip one field payload according to its tag.
///
/// Groups are skipped recursively until their matching end-group tag. The
/// `depth` parameter guards against deeply nested or unterminated groups.
pub fn WireReader::skip_tag(
  self : WireReader,
  tag : Tag,
  depth? : Int = 0,
) -> Unit raise @types.DecodeError {
  match tag.wire_type {
    Varint => {
      let _ = self.read_varint()
    }
    Fixed64 => self.skip(8)
    LengthDelimited => {
      let length = self.read_length()
      self.skip(length)
    }
    StartGroup => {
      if depth >= MAX_GROUP_DEPTH {
        raise @types.RecursionLimitExceeded(limit=MAX_GROUP_DEPTH)
      }
      while true {
        if self.is_empty() {
          raise @types.UnterminatedGroup(offset=self.position)
        }
        let inner = self.next_tag()
        if inner.wire_type == EndGroup {
          if inner.field_number != tag.field_number {
            raise @types.MismatchedEndGroup(
              offset=self.position,
              expected=tag.field_number,
              actual=inner.field_number,
            )
          }
          break
        }
        self.skip_tag(inner, depth=depth + 1)
      }
    }
    EndGroup => raise @types.UnexpectedEndGroup(offset=self.position)
    Fixed32 => self.skip(4)
  }
}
