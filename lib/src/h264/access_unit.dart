import 'dart:typed_data';

import 'nal_unit.dart';

/// One coded picture: every NAL unit that belongs to a single video frame.
class AccessUnit {
  /// Creates an access unit from its NAL units.
  AccessUnit(this.nalUnits, {Duration? receivedAt})
    : receivedAt = receivedAt ?? Duration.zero;

  /// NAL units in decoding order.
  final List<NalUnit> nalUnits;

  /// Monotonic time at which the access unit was completed.
  final Duration receivedAt;

  /// Whether this access unit is an IDR picture (a keyframe).
  bool get isKeyframe => nalUnits.any((n) => n.isKeyframe);

  /// Whether this access unit contains any picture data.
  bool get hasPicture => nalUnits.any((n) => n.isVcl);

  /// The NAL unit of [type] in this access unit, if present.
  NalUnit? firstOfType(int type) {
    for (final nal in nalUnits) {
      if (nal.type == type) return nal;
    }
    return null;
  }

  /// Total payload size in bytes (excluding start codes / length prefixes).
  int get byteLength => nalUnits.fold(0, (sum, n) => sum + n.bytes.length);

  /// Serialises the access unit as Annex-B (4-byte start codes).
  Uint8List toAnnexB({Iterable<NalUnit> prepend = const []}) {
    final units = [...prepend, ...nalUnits];
    final out = Uint8List(units.fold(0, (s, n) => s + 4 + n.bytes.length));
    var offset = 0;
    for (final nal in units) {
      out[offset + 3] = 1;
      out.setRange(offset + 4, offset + 4 + nal.bytes.length, nal.bytes);
      offset += 4 + nal.bytes.length;
    }
    return out;
  }

  /// Serialises picture-related NAL units as AVCC (4-byte big-endian length
  /// prefixes), as stored in MP4 samples. Parameter sets and delimiters are
  /// omitted because MP4 carries them in the `avcC` box.
  Uint8List toAvcc() {
    final units = nalUnits.where(
      (n) =>
          n.type != NalUnitType.accessUnitDelimiter &&
          n.type != NalUnitType.sps &&
          n.type != NalUnitType.pps &&
          n.type != NalUnitType.filler,
    );
    final total = units.fold(0, (s, n) => s + 4 + n.bytes.length);
    final out = Uint8List(total);
    final view = ByteData.sublistView(out);
    var offset = 0;
    for (final nal in units) {
      view.setUint32(offset, nal.bytes.length);
      out.setRange(offset + 4, offset + 4 + nal.bytes.length, nal.bytes);
      offset += 4 + nal.bytes.length;
    }
    return out;
  }

  @override
  String toString() =>
      'AccessUnit(${isKeyframe ? 'key, ' : ''}${nalUnits.map((n) => n.type).join(',')})';
}

/// Groups a sequence of [NalUnit]s into [AccessUnit]s, following the
/// access-unit boundary rules of ITU-T H.264 §7.4.1.2.3.
///
/// Because a boundary is only known when the next picture starts, each
/// access unit is emitted when the first NAL unit of the following one
/// arrives (one frame of latency), or on [flush].
class AccessUnitAssembler {
  /// Creates an assembler. [clock] supplies the receive timestamp.
  AccessUnitAssembler({Duration Function()? clock})
    : _clock = clock ?? _defaultClock;

  static final Stopwatch _stopwatch = Stopwatch()..start();
  static Duration _defaultClock() => _stopwatch.elapsed;

  final Duration Function() _clock;
  final List<NalUnit> _pending = [];
  bool _pendingHasPicture = false;

  /// Adds [nal] and returns the access unit it completed, if any.
  AccessUnit? add(NalUnit nal) {
    AccessUnit? completed;
    if (_pending.isNotEmpty && _startsNewAccessUnit(nal)) {
      completed = _take();
    }
    _pending.add(nal);
    if (nal.isVcl) _pendingHasPicture = true;
    return completed;
  }

  /// Emits the pending access unit, if it contains a picture.
  AccessUnit? flush() => _pending.isEmpty ? null : _take();

  /// Discards pending NAL units.
  void reset() {
    _pending.clear();
    _pendingHasPicture = false;
  }

  bool _startsNewAccessUnit(NalUnit nal) {
    // Until the pending unit has a picture, everything (parameter sets, SEI,
    // delimiters) is a prefix of the picture that follows.
    if (!_pendingHasPicture) return false;
    final type = nal.type;
    if (type == NalUnitType.accessUnitDelimiter ||
        type == NalUnitType.sei ||
        type == NalUnitType.sps ||
        type == NalUnitType.pps ||
        (type >= 14 && type <= 18)) {
      return true;
    }
    return nal.isVcl && nal.isFirstSliceOfPicture;
  }

  AccessUnit? _take() {
    final hasPicture = _pendingHasPicture;
    final units = List<NalUnit>.of(_pending);
    reset();
    return hasPicture ? AccessUnit(units, receivedAt: _clock()) : null;
  }
}
