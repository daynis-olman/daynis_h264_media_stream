import 'dart:convert';
import 'dart:typed_data';

import 'package:daynis_h264_media_stream/daynis_h264_media_stream.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture_helpers.dart';

/// Lists (type, offset, size) of the boxes directly inside [data][start, end).
List<(String, int, int)> boxes(Uint8List data, [int start = 0, int? end]) {
  final view = ByteData.sublistView(data);
  final out = <(String, int, int)>[];
  var offset = start;
  end ??= data.length;
  while (offset < end) {
    final size = view.getUint32(offset);
    out.add((ascii.decode(data.sublist(offset + 4, offset + 8)), offset, size));
    if (size < 8) break;
    offset += size;
  }
  return out;
}

void main() {
  final units = fixtureAccessUnits();
  final first = units.first;
  final muxer = Fmp4Muxer(
    sps: first.firstOfType(NalUnitType.sps)!,
    pps: first.firstOfType(NalUnitType.pps)!,
  );

  test('init segment is ftyp + moov with an avcC configuration', () {
    final init = muxer.initSegment();
    final top = boxes(init);
    expect(top.map((b) => b.$1), ['ftyp', 'moov']);
    expect(top.last.$2 + top.last.$3, init.length);
    final text = latin1.decode(init);
    for (final type in [
      'mvhd',
      'trak',
      'tkhd',
      'mdhd',
      'hdlr',
      'stsd',
      'avc1',
      'avcC',
      'mvex',
      'trex',
    ]) {
      expect(text, contains(type), reason: 'missing $type');
    }
    expect(muxer.mimeType, 'video/mp4; codecs="${muxer.info.codecString}"');
  });

  test('media segment is moof + mdat with a correct data offset', () {
    final samples = [
      for (final unit in units.take(3))
        Fmp4Sample.fromAccessUnit(unit, duration: 3000),
    ];
    final segment = muxer.mediaSegment(
      samples,
      baseMediaDecodeTime: 0x123456789,
    );
    final top = boxes(segment);
    expect(top.map((b) => b.$1), ['moof', 'mdat']);
    final moofSize = top.first.$3;
    final mdatPayload = segment.sublist(moofSize + 8);
    expect(mdatPayload, [for (final s in samples) ...s.data]);

    final view = ByteData.sublistView(segment);
    final trun = latin1.decode(segment).indexOf('trun') - 4;
    // fullbox header (12) + sample_count (4) -> data_offset
    expect(view.getUint32(trun + 12), 3);
    expect(view.getInt32(trun + 16), moofSize + 8);
    // First sample flags mark a sync sample, the second a non-sync one.
    expect(view.getUint32(trun + 20 + 8), 0x02000000);
    expect(view.getUint32(trun + 20 + 12 + 8), 0x01010000);

    final tfdt = latin1.decode(segment).indexOf('tfdt') - 4;
    expect(view.getUint32(tfdt + 12), 0x1);
    expect(view.getUint32(tfdt + 16), 0x23456789);
  });

  test('rejects empty sample lists', () {
    expect(
      () => muxer.mediaSegment(const [], baseMediaDecodeTime: 0),
      throwsArgumentError,
    );
  });
}
