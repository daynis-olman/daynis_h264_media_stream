import 'dart:typed_data';

import 'bit_reader.dart';

/// H.264 NAL unit types used by this package (ITU-T H.264 Table 7-1).
abstract final class NalUnitType {
  /// Coded slice of a non-IDR picture.
  static const int sliceNonIdr = 1;

  /// Coded slice of an IDR (keyframe) picture.
  static const int sliceIdr = 5;

  /// Supplemental enhancement information.
  static const int sei = 6;

  /// Sequence parameter set.
  static const int sps = 7;

  /// Picture parameter set.
  static const int pps = 8;

  /// Access unit delimiter.
  static const int accessUnitDelimiter = 9;

  /// End of sequence.
  static const int endOfSequence = 10;

  /// End of stream.
  static const int endOfStream = 11;

  /// Filler data.
  static const int filler = 12;
}

/// A single H.264 NAL unit, without its Annex-B start code.
class NalUnit {
  /// Wraps the raw NAL unit bytes (header byte included, start code excluded).
  NalUnit(this.bytes) : assert(bytes.isNotEmpty);

  /// The NAL unit bytes, starting with the one-byte NAL header.
  final Uint8List bytes;

  /// The `nal_unit_type` field (0–31).
  int get type => bytes[0] & 0x1f;

  /// The `nal_ref_idc` field (0–3).
  int get refIdc => (bytes[0] >> 5) & 0x03;

  /// Whether this NAL unit carries coded picture data (a slice).
  bool get isVcl => type >= 1 && type <= 5;

  /// Whether this NAL unit is an IDR slice, i.e. part of a keyframe.
  bool get isKeyframe => type == NalUnitType.sliceIdr;

  /// For slice NAL units, whether this is the first slice of a picture
  /// (`first_mb_in_slice == 0`). Always `false` for non-slice units.
  bool get isFirstSliceOfPicture {
    if (!isVcl || bytes.length < 2) return false;
    // first_mb_in_slice is the first ue(v) after the header; a leading 1 bit
    // encodes the value 0. Emulation prevention cannot affect the first bit.
    try {
      return BitReader(Uint8List.sublistView(bytes, 1)).readUe() == 0;
    } on FormatException {
      return false;
    }
  }

  @override
  String toString() => 'NalUnit(type: $type, ${bytes.length} bytes)';
}
