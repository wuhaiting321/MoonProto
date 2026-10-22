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
/// Encode one uplink batch the way a device SDK would:
///
///   1: string device_id
///   2: uint64 collected_at_ms
///   3: double temperature_c
///   4: uint32 battery_mv
///   5: enum status (2 = OK)
///   6: packed sint32 samples
fn encode_batch() -> Bytes raise {
  let samples : Array[@types.ScalarValue] = [
    @types.ScalarValue::SInt32(-3),
    @types.ScalarValue::SInt32(0),
    @types.ScalarValue::SInt32(5),
    @types.ScalarValue::SInt32(12),
    @types.ScalarValue::SInt32(-8),
    @types.ScalarValue::SInt32(8),
  ]
  let encoder = @codec.Encoder::new()
  encoder.write_string(1, "sensor-042")
  encoder.write_scalar_field(2, @types.ScalarValue::UInt64(1730000000000UL))
  encoder.write_scalar_field(3, @types.ScalarValue::Double(23.5))
  encoder.write_scalar_field(4, @types.ScalarValue::UInt32(3700U))
  encoder.write_scalar_field(5, @types.ScalarValue::Enum(2))
  encoder.write_packed_scalar_field(6, samples)
  encoder.finish()
}

///|
/// Decode the batch on the cloud side without any generated schema, then
/// summarize the packed samples.
fn run() -> Unit raise {
  let bytes = encode_batch()
  println(
    "uplink batch " + bytes.length().to_string() + " bytes: " + hex(bytes),
  )
  let mut device = ""
  let mut collected_at : UInt64 = 0UL
  let mut temperature : Double = 0.0
  let mut battery : UInt32 = 0U
  let mut status = 0
  let samples : Array[Int32] = []
  let decoder = @codec.Decoder::new(bytes)
  while !decoder.is_empty() {
    let tag = decoder.next_tag().unwrap()
    match tag.field_number() {
      1 => device = decoder.read_string()
      2 =>
        collected_at = match
          decoder.read_scalar_field(tag, @types.ScalarType::UInt64) {
          @types.ScalarValue::UInt64(value) => value
          _ => 0UL
        }
      3 =>
        temperature = match
          decoder.read_scalar_field(tag, @types.ScalarType::Double) {
          @types.ScalarValue::Double(value) => value
          _ => 0.0
        }
      4 =>
        battery = match
          decoder.read_scalar_field(tag, @types.ScalarType::UInt32) {
          @types.ScalarValue::UInt32(value) => value
          _ => 0U
        }
      5 =>
        status = match decoder.read_scalar_field(tag, @types.ScalarType::Enum) {
          @types.ScalarValue::Enum(value) => value
          _ => 0
        }
      6 => {
        let values = decoder.read_packed_scalar_field(
          tag,
          @types.ScalarType::SInt32,
        )
        for value in values {
          samples.push(
            match value {
              @types.ScalarValue::SInt32(v) => v
              _ => 0
            },
          )
        }
      }
      _ => decoder.skip_tag(tag)
    }
  }
  let mut minimum = 0
  let mut maximum = 0
  let mut total = 0
  let mut first = true
  for value in samples {
    if first || value < minimum {
      minimum = value
    }
    if first || value > maximum {
      maximum = value
    }
    first = false
    total = total + value
  }
  println("device=" + device + " collected_at=" + collected_at.to_string())
  println(
    "temperature=" +
    temperature.to_string() +
    "C battery=" +
    battery.to_string() +
    "mV status=" +
    status.to_string() +
    (if status == 2 { "(OK)" } else { "(UNKNOWN)" }),
  )
  println(
    "samples=" +
    samples.length().to_string() +
    " min=" +
    minimum.to_string() +
    " max=" +
    maximum.to_string() +
    " total=" +
    total.to_string(),
  )
}

///|
fn main {
  run() catch {
    error => println("example failed: " + error.to_string())
  }
}
