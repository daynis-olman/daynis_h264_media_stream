import 'dart:typed_data';

/// Reads bits and Exp-Golomb codes from an H.264 RBSP (raw byte sequence
/// payload, i.e. with emulation-prevention bytes already removed).
///
/// Arithmetic avoids 64-bit shifts so it behaves identically when compiled
/// to JavaScript, where bitwise operators are limited to 32 bits.
class BitReader {
  /// Creates a reader over [data], starting at the first bit.
  BitReader(this._data);

  final Uint8List _data;
  int _bitOffset = 0;

  /// Number of bits that have not been read yet.
  int get bitsRemaining => _data.length * 8 - _bitOffset;

  /// Reads a single bit.
  int readBit() {
    if (_bitOffset >= _data.length * 8) {
      throw const FormatException('Unexpected end of H.264 bitstream');
    }
    final byte = _data[_bitOffset >> 3];
    final bit = (byte >> (7 - (_bitOffset & 7))) & 1;
    _bitOffset++;
    return bit;
  }

  /// Reads a single bit as a boolean flag.
  bool readFlag() => readBit() == 1;

  /// Reads [count] bits (up to 32) as an unsigned integer.
  int readBits(int count) {
    var value = 0;
    for (var i = 0; i < count; i++) {
      value = value * 2 + readBit();
    }
    return value;
  }

  /// Skips [count] bits.
  void skipBits(int count) {
    if (count > bitsRemaining) {
      throw const FormatException('Unexpected end of H.264 bitstream');
    }
    _bitOffset += count;
  }

  /// Reads an unsigned Exp-Golomb code, `ue(v)`.
  int readUe() {
    var leadingZeros = 0;
    while (readBit() == 0) {
      leadingZeros++;
      if (leadingZeros > 31) {
        throw const FormatException('Invalid Exp-Golomb code');
      }
    }
    if (leadingZeros == 0) return 0;
    var prefix = 1;
    for (var i = 0; i < leadingZeros; i++) {
      prefix *= 2;
    }
    return prefix - 1 + readBits(leadingZeros);
  }

  /// Reads a signed Exp-Golomb code, `se(v)`.
  int readSe() {
    final codeNum = readUe();
    return codeNum.isOdd ? (codeNum + 1) ~/ 2 : -(codeNum ~/ 2);
  }
}

/// Removes emulation-prevention bytes (`0x000003` → `0x0000`) from a NAL
/// unit payload, producing its RBSP.
Uint8List removeEmulationPrevention(Uint8List data) {
  final out = BytesBuilder(copy: false);
  var zeros = 0;
  var runStart = 0;
  for (var i = 0; i < data.length; i++) {
    final byte = data[i];
    if (zeros >= 2 && byte == 0x03) {
      out.add(Uint8List.sublistView(data, runStart, i));
      runStart = i + 1;
      zeros = 0;
      continue;
    }
    zeros = byte == 0 ? zeros + 1 : 0;
  }
  if (runStart == 0) return data;
  out.add(Uint8List.sublistView(data, runStart));
  return out.takeBytes();
}
