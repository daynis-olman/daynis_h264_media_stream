import 'dart:typed_data';

import 'nal_unit.dart';

/// Incrementally splits an H.264 Annex-B byte stream into [NalUnit]s.
///
/// Chunks may be split anywhere, including in the middle of a start code.
/// Bytes before the first start code are discarded. A NAL unit is emitted
/// once the following start code arrives, or on [flush].
class AnnexBSplitter {
  Uint8List _buffer = Uint8List(0);
  int _length = 0;
  int _nalStart = -1;
  int _scanFrom = 0;

  /// Appends [chunk] and returns every NAL unit completed by it.
  List<NalUnit> add(Uint8List chunk) {
    _append(chunk);
    final units = <NalUnit>[];
    var i = _scanFrom;
    while (i + 2 < _length) {
      // Fast skip: a start code needs buffer[i + 2] <= 1.
      final b2 = _buffer[i + 2];
      if (b2 > 1) {
        i += 3;
        continue;
      }
      if (_buffer[i] == 0 && _buffer[i + 1] == 0 && b2 == 1) {
        if (_nalStart >= 0) _emit(_nalStart, i, units);
        _nalStart = i + 3;
        i += 3;
      } else {
        i++;
      }
    }
    _scanFrom = i;
    _compact();
    return units;
  }

  /// Emits the trailing NAL unit, if any, and resets the splitter.
  List<NalUnit> flush() {
    final units = <NalUnit>[];
    if (_nalStart >= 0) _emit(_nalStart, _length, units);
    reset();
    return units;
  }

  /// Discards all buffered data.
  void reset() {
    _buffer = Uint8List(0);
    _length = 0;
    _nalStart = -1;
    _scanFrom = 0;
  }

  void _emit(int start, int end, List<NalUnit> out) {
    // Trailing zero bytes belong to the next (4-byte) start code or are
    // trailing_zero_8bits; neither is part of the NAL unit.
    while (end > start && _buffer[end - 1] == 0) {
      end--;
    }
    if (end > start) {
      out.add(
        NalUnit(Uint8List.fromList(Uint8List.sublistView(_buffer, start, end))),
      );
    }
  }

  void _append(Uint8List chunk) {
    final needed = _length + chunk.length;
    if (needed > _buffer.length) {
      final grown = Uint8List(needed < 4096 ? 4096 : needed * 2);
      grown.setRange(0, _length, _buffer);
      _buffer = grown;
    }
    _buffer.setRange(_length, needed, chunk);
    _length = needed;
  }

  void _compact() {
    // Keep only the bytes that are still needed: the open NAL unit, or the
    // last two bytes that could begin a start code.
    final keepFrom = _nalStart >= 0
        ? _nalStart
        : (_length - 2).clamp(0, _length);
    if (keepFrom == 0) return;
    _buffer.setRange(0, _length - keepFrom, _buffer, keepFrom);
    _length -= keepFrom;
    _scanFrom -= keepFrom;
    if (_scanFrom < 0) _scanFrom = 0;
    if (_nalStart >= 0) _nalStart -= keepFrom;
  }
}
