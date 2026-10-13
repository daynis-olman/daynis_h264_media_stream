import 'dart:convert';
import 'dart:typed_data';

import '../h264/access_unit.dart';
import '../h264/nal_unit.dart';
import '../h264/sps.dart';

/// A single video sample for [Fmp4Muxer.mediaSegment].
class Fmp4Sample {
  /// Creates a sample from AVCC-formatted [data] lasting [duration] ticks.
  const Fmp4Sample({
    required this.data,
    required this.duration,
    required this.isKeyframe,
  });

  /// Creates a sample from an [AccessUnit].
  factory Fmp4Sample.fromAccessUnit(AccessUnit unit, {required int duration}) =>
      Fmp4Sample(
        data: unit.toAvcc(),
        duration: duration,
        isKeyframe: unit.isKeyframe,
      );

  /// Length-prefixed (AVCC) NAL units.
  final Uint8List data;

  /// Sample duration in [Fmp4Muxer.timescale] ticks.
  final int duration;

  /// Whether the sample is a sync sample (IDR).
  final bool isKeyframe;
}

/// Writes fragmented MP4 (ISO BMFF) for a single H.264 track, suitable for
/// Media Source Extensions `SourceBuffer.appendBuffer`.
///
/// Call [initSegment] once, then [mediaSegment] for each batch of samples.
class Fmp4Muxer {
  /// Creates a muxer for the stream described by [sps] and [pps].
  Fmp4Muxer({required this.sps, required this.pps, this.timescale = 90000})
    : info = SpsInfo.parse(sps);

  /// The sequence parameter set NAL unit.
  final NalUnit sps;

  /// The picture parameter set NAL unit.
  final NalUnit pps;

  /// Media timescale in ticks per second.
  final int timescale;

  /// Parsed [sps].
  final SpsInfo info;

  int _sequenceNumber = 0;

  /// The MSE mime type for this stream, e.g. `video/mp4; codecs="avc1.64001f"`.
  String get mimeType => 'video/mp4; codecs="${info.codecString}"';

  /// The initialisation segment (`ftyp` + `moov`).
  Uint8List initSegment() {
    final b = _BoxWriter();
    b.box('ftyp', () {
      b.fourcc('isom');
      b.u32(0x200);
      for (final brand in const ['isom', 'iso6', 'avc1', 'mp41']) {
        b.fourcc(brand);
      }
    });
    b.box('moov', () {
      b.fullBox('mvhd', 0, 0, () {
        b.u32(0); // creation_time
        b.u32(0); // modification_time
        b.u32(1000); // timescale
        b.u32(0); // duration
        b.u32(0x00010000); // rate 1.0
        b.u16(0x0100); // volume 1.0
        b.zeros(10);
        _matrix(b);
        b.zeros(24); // pre_defined
        b.u32(2); // next_track_ID
      });
      b.box('trak', () {
        b.fullBox('tkhd', 0, 0x000003, () {
          b.u32(0);
          b.u32(0);
          b.u32(1); // track_ID
          b.u32(0);
          b.u32(0); // duration
          b.zeros(8);
          b.u16(0); // layer
          b.u16(0); // alternate_group
          b.u16(0); // volume
          b.u16(0);
          _matrix(b);
          b.u32(info.width * 0x10000);
          b.u32(info.height * 0x10000);
        });
        b.box('mdia', () {
          b.fullBox('mdhd', 0, 0, () {
            b.u32(0);
            b.u32(0);
            b.u32(timescale);
            b.u32(0);
            b.u16(0x55c4); // language: und
            b.u16(0);
          });
          b.fullBox('hdlr', 0, 0, () {
            b.u32(0);
            b.fourcc('vide');
            b.zeros(12);
            b.bytes(ascii.encode('VideoHandler'));
            b.u8(0);
          });
          b.box('minf', () {
            b.fullBox('vmhd', 0, 1, () => b.zeros(8));
            b.box('dinf', () {
              b.fullBox('dref', 0, 0, () {
                b.u32(1);
                b.fullBox('url ', 0, 1, () {});
              });
            });
            b.box('stbl', () {
              b.fullBox('stsd', 0, 0, () {
                b.u32(1);
                _avc1(b);
              });
              b.fullBox('stts', 0, 0, () => b.u32(0));
              b.fullBox('stsc', 0, 0, () => b.u32(0));
              b.fullBox('stsz', 0, 0, () {
                b.u32(0);
                b.u32(0);
              });
              b.fullBox('stco', 0, 0, () => b.u32(0));
            });
          });
        });
      });
      b.box('mvex', () {
        b.fullBox('trex', 0, 0, () {
          b.u32(1); // track_ID
          b.u32(1); // default_sample_description_index
          b.u32(0);
          b.u32(0);
          b.u32(0);
        });
      });
    });
    return b.takeBytes();
  }

  /// A media segment (`moof` + `mdat`) holding [samples], the first of which
  /// is decoded at [baseMediaDecodeTime] ticks.
  Uint8List mediaSegment(
    List<Fmp4Sample> samples, {
    required int baseMediaDecodeTime,
  }) {
    if (samples.isEmpty) {
      throw ArgumentError.value(samples, 'samples', 'must not be empty');
    }
    _sequenceNumber++;
    final b = _BoxWriter();
    late int dataOffsetPosition;
    final moofStart = b.length;
    b.box('moof', () {
      b.fullBox('mfhd', 0, 0, () => b.u32(_sequenceNumber));
      b.box('traf', () {
        b.fullBox('tfhd', 0, 0x020000, () => b.u32(1)); // default-base-is-moof
        b.fullBox('tfdt', 1, 0, () => b.u64(baseMediaDecodeTime));
        // data-offset, sample-duration, sample-size, sample-flags present.
        b.fullBox('trun', 0, 0x000701, () {
          b.u32(samples.length);
          dataOffsetPosition = b.length;
          b.u32(0); // data_offset, patched below
          for (final s in samples) {
            b.u32(s.duration);
            b.u32(s.data.length);
            // Sync: depends_on=2. Non-sync: depends_on=1, is_non_sync_sample=1.
            b.u32(s.isKeyframe ? 0x02000000 : 0x01010000);
          }
        });
      });
    });
    final moofSize = b.length - moofStart;
    b.patchU32(dataOffsetPosition, moofSize + 8);
    b.box('mdat', () {
      for (final s in samples) {
        b.bytes(s.data);
      }
    });
    return b.takeBytes();
  }

  void _avc1(_BoxWriter b) {
    b.box('avc1', () {
      b.zeros(6);
      b.u16(1); // data_reference_index
      b.zeros(16); // pre_defined + reserved
      b.u16(info.width);
      b.u16(info.height);
      b.u32(0x00480000); // 72 dpi
      b.u32(0x00480000);
      b.u32(0);
      b.u16(1); // frame_count
      b.zeros(32); // compressorname
      b.u16(0x0018); // depth
      b.u16(0xffff); // pre_defined = -1
      b.box('avcC', () {
        b.u8(1); // configurationVersion
        b.u8(sps.bytes[1]); // AVCProfileIndication
        b.u8(sps.bytes[2]); // profile_compatibility
        b.u8(sps.bytes[3]); // AVCLevelIndication
        b.u8(0xff); // lengthSizeMinusOne = 3
        b.u8(0xe1); // one SPS
        b.u16(sps.bytes.length);
        b.bytes(sps.bytes);
        b.u8(1); // one PPS
        b.u16(pps.bytes.length);
        b.bytes(pps.bytes);
      });
    });
  }

  static void _matrix(_BoxWriter b) {
    for (final v in const [
      0x00010000,
      0,
      0,
      0,
      0x00010000,
      0,
      0,
      0,
      0x40000000,
    ]) {
      b.u32(v);
    }
  }
}

class _BoxWriter {
  final BytesBuilder _out = BytesBuilder();
  final List<(int, int)> _patchPositions = [];
  final _scratch = ByteData(8);

  int get length => _out.length;

  void box(String type, void Function() body) {
    final start = _out.length;
    u32(0); // size, patched once the body is written
    fourcc(type);
    body();
    patchU32(start, _out.length - start);
  }

  void fullBox(String type, int version, int flags, void Function() body) {
    box(type, () {
      u8(version);
      u8((flags >> 16) & 0xff);
      u8((flags >> 8) & 0xff);
      u8(flags & 0xff);
      body();
    });
  }

  void u8(int v) => _out.addByte(v & 0xff);

  void u16(int v) {
    _scratch.setUint16(0, v & 0xffff);
    _out.add(Uint8List.sublistView(_scratch, 0, 2));
  }

  void u32(int v) {
    _scratch.setUint32(0, v & 0xffffffff);
    _out.add(Uint8List.sublistView(_scratch, 0, 4));
  }

  /// 64-bit write without ByteData.setUint64, which dart2js does not support.
  void u64(int v) {
    u32(v ~/ 0x100000000);
    u32(v % 0x100000000);
  }

  void fourcc(String s) => _out.add(ascii.encode(s));

  void zeros(int count) => _out.add(Uint8List(count));

  void bytes(List<int> data) => _out.add(data);

  void patchU32(int position, int value) {
    _patchPositions.add((position, value));
  }

  Uint8List takeBytes() {
    final bytes = _out.takeBytes();
    final view = ByteData.sublistView(bytes);
    for (final (position, value) in _patchPositions) {
      view.setUint32(position, value);
    }
    _patchPositions.clear();
    return bytes;
  }
}
