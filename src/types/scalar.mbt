// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// The scalar element types defined by Protocol Buffers v3.
///
/// `string` and `bytes` are length-delimited message fields rather than
/// scalars, so they are handled by the encoder and decoder directly instead of
/// appearing in this enumeration.
pub(all) enum ScalarType {
  Double
  Float
  Int32
  Int64
  UInt32
  UInt64
  SInt32
  SInt64
  Fixed32
  Fixed64
  SFixed32
  SFixed64
  Bool
  Enum
} derive(Debug, Eq)

///|
/// Human-readable protobuf spelling of a scalar type.
pub fn ScalarType::name(self : ScalarType) -> String {
  match self {
    Double => "double"
    Float => "float"
    Int32 => "int32"
    Int64 => "int64"
    UInt32 => "uint32"
    UInt64 => "uint64"
    SInt32 => "sint32"
    SInt64 => "sint64"
    Fixed32 => "fixed32"
    Fixed64 => "fixed64"
    SFixed32 => "sfixed32"
    SFixed64 => "sfixed64"
    Bool => "bool"
    Enum => "enum"
  }
}

///|
/// A dynamically typed protobuf scalar value.
pub(all) enum ScalarValue {
  Double(Double)
  Float(Float)
  Int32(Int)
  Int64(Int64)
  UInt32(UInt)
  UInt64(UInt64)
  SInt32(Int)
  SInt64(Int64)
  Fixed32(UInt)
  Fixed64(UInt64)
  SFixed32(Int)
  SFixed64(Int64)
  Bool(Bool)
  Enum(Int)
} derive(Debug, Eq)

///|
/// The protobuf scalar type of a value.
pub fn ScalarValue::scalar_type(self : ScalarValue) -> ScalarType {
  match self {
    Double(_) => Double
    Float(_) => Float
    Int32(_) => Int32
    Int64(_) => Int64
    UInt32(_) => UInt32
    UInt64(_) => UInt64
    SInt32(_) => SInt32
    SInt64(_) => SInt64
    Fixed32(_) => Fixed32
    Fixed64(_) => Fixed64
    SFixed32(_) => SFixed32
    SFixed64(_) => SFixed64
    Bool(_) => Bool
    Enum(_) => Enum
  }
}
