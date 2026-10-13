import 'dart:typed_data';

import 'bit_reader.dart';
import 'nal_unit.dart';

const _highProfiles = {
  100,
  110,
  122,
  244,
  44,
  83,
  86,
  118,
  128,
  138,
  139,
  134,
  135,
};

/// The fields of an H.264 sequence parameter set (SPS) needed to configure a
/// decoder or an MP4 container.
class SpsInfo {
  const SpsInfo._({
    required this.profileIdc,
    required this.constraintFlags,
    required this.levelIdc,
    required this.chromaFormatIdc,
    required this.width,
    required this.height,
    this.frameRate,
  });

  /// Parses an SPS NAL unit (including its one-byte header).
  ///
  /// Throws a [FormatException] if [sps] is not a valid sequence parameter
  /// set.
  factory SpsInfo.parse(NalUnit sps) {
    if (sps.type != NalUnitType.sps) {
      throw FormatException('Expected an SPS NAL unit, got type ${sps.type}');
    }
    final r = BitReader(
      removeEmulationPrevention(Uint8List.sublistView(sps.bytes, 1)),
    );
    final profileIdc = r.readBits(8);
    final constraintFlags = r.readBits(8);
    final levelIdc = r.readBits(8);
    r.readUe(); // seq_parameter_set_id

    var chromaFormatIdc = 1;
    var separateColourPlane = false;
    if (_highProfiles.contains(profileIdc)) {
      chromaFormatIdc = r.readUe();
      if (chromaFormatIdc == 3) separateColourPlane = r.readFlag();
      r.readUe(); // bit_depth_luma_minus8
      r.readUe(); // bit_depth_chroma_minus8
      r.readFlag(); // qpprime_y_zero_transform_bypass_flag
      if (r.readFlag()) {
        // seq_scaling_matrix_present_flag
        final lists = chromaFormatIdc == 3 ? 12 : 8;
        for (var i = 0; i < lists; i++) {
          if (r.readFlag()) _skipScalingList(r, i < 6 ? 16 : 64);
        }
      }
    }

    r.readUe(); // log2_max_frame_num_minus4
    final picOrderCntType = r.readUe();
    if (picOrderCntType == 0) {
      r.readUe(); // log2_max_pic_order_cnt_lsb_minus4
    } else if (picOrderCntType == 1) {
      r.readFlag(); // delta_pic_order_always_zero_flag
      r.readSe(); // offset_for_non_ref_pic
      r.readSe(); // offset_for_top_to_bottom_field
      final cycle = r.readUe();
      for (var i = 0; i < cycle; i++) {
        r.readSe();
      }
    }
    r.readUe(); // max_num_ref_frames
    r.readFlag(); // gaps_in_frame_num_value_allowed_flag
    final widthInMbs = r.readUe() + 1;
    final heightInMapUnits = r.readUe() + 1;
    final frameMbsOnly = r.readFlag();
    if (!frameMbsOnly) r.readFlag(); // mb_adaptive_frame_field_flag
    r.readFlag(); // direct_8x8_inference_flag

    var cropLeft = 0, cropRight = 0, cropTop = 0, cropBottom = 0;
    if (r.readFlag()) {
      cropLeft = r.readUe();
      cropRight = r.readUe();
      cropTop = r.readUe();
      cropBottom = r.readUe();
    }

    final frameHeightFactor = frameMbsOnly ? 1 : 2;
    final int cropUnitX;
    final int cropUnitY;
    if (chromaFormatIdc == 0 || separateColourPlane) {
      cropUnitX = 1;
      cropUnitY = frameHeightFactor;
    } else {
      final subWidthC = chromaFormatIdc == 3 ? 1 : 2;
      final subHeightC = chromaFormatIdc == 1 ? 2 : 1;
      cropUnitX = subWidthC;
      cropUnitY = subHeightC * frameHeightFactor;
    }
    final width = widthInMbs * 16 - cropUnitX * (cropLeft + cropRight);
    final height =
        frameHeightFactor * heightInMapUnits * 16 -
        cropUnitY * (cropTop + cropBottom);

    double? frameRate;
    try {
      if (r.readFlag()) frameRate = _readVuiFrameRate(r);
    } on FormatException {
      // VUI is optional; a truncated VUI only loses the frame rate hint.
    }

    return SpsInfo._(
      profileIdc: profileIdc,
      constraintFlags: constraintFlags,
      levelIdc: levelIdc,
      chromaFormatIdc: chromaFormatIdc,
      width: width,
      height: height,
      frameRate: frameRate,
    );
  }

  /// `profile_idc`, e.g. 66 (Baseline), 77 (Main), 100 (High).
  final int profileIdc;

  /// The `constraint_set*_flag` byte.
  final int constraintFlags;

  /// `level_idc`, e.g. 31 for level 3.1.
  final int levelIdc;

  /// `chroma_format_idc` (1 = 4:2:0).
  final int chromaFormatIdc;

  /// Display width in pixels, after cropping.
  final int width;

  /// Display height in pixels, after cropping.
  final int height;

  /// Frame rate from the VUI timing info, when the encoder signalled it.
  final double? frameRate;

  /// RFC 6381 codec string, e.g. `avc1.64001f`, for WebCodecs and MSE.
  String get codecString =>
      'avc1.${_hex(profileIdc)}${_hex(constraintFlags)}${_hex(levelIdc)}';

  /// Human-readable profile name.
  String get profileName => switch (profileIdc) {
    66 => 'Baseline',
    77 => 'Main',
    88 => 'Extended',
    100 => 'High',
    110 => 'High 10',
    122 => 'High 4:2:2',
    244 => 'High 4:4:4',
    _ => 'Profile $profileIdc',
  };

  @override
  String toString() =>
      'SpsInfo($profileName, level ${levelIdc / 10}, '
      '${width}x$height${frameRate != null ? ', ${frameRate!.toStringAsFixed(2)} fps' : ''})';

  static String _hex(int v) => v.toRadixString(16).padLeft(2, '0');

  static void _skipScalingList(BitReader r, int size) {
    var lastScale = 8;
    var nextScale = 8;
    for (var j = 0; j < size; j++) {
      if (nextScale != 0) {
        nextScale = (lastScale + r.readSe() + 256) % 256;
      }
      lastScale = nextScale == 0 ? lastScale : nextScale;
    }
  }

  static double? _readVuiFrameRate(BitReader r) {
    if (r.readFlag()) {
      // aspect_ratio_info_present_flag
      if (r.readBits(8) == 255) {
        r.skipBits(32); // Extended_SAR: sar_width, sar_height
      }
    }
    if (r.readFlag()) {
      r.readFlag(); // overscan_info_present → overscan_appropriate
    }
    if (r.readFlag()) {
      // video_signal_type_present_flag
      r.skipBits(4); // video_format, video_full_range_flag
      if (r.readFlag()) r.skipBits(24); // colour primaries, transfer, matrix
    }
    if (r.readFlag()) {
      // chroma_loc_info_present_flag
      r.readUe();
      r.readUe();
    }
    if (!r.readFlag()) return null; // timing_info_present_flag
    final numUnitsInTick = r.readBits(32);
    final timeScale = r.readBits(32);
    if (numUnitsInTick == 0 || timeScale == 0) return null;
    return timeScale / (2 * numUnitsInTick);
  }
}
