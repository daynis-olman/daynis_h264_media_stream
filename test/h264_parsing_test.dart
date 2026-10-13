import 'dart:typed_data';

import 'package:daynis_h264_media_stream/daynis_h264_media_stream.dart';
import 'package:daynis_h264_media_stream/src/h264/bit_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture_helpers.dart';

void main() {
  group('BitReader', () {
    test('reads Exp-Golomb codes', () {
      // 1 | 010 | 011 | 00100 | 00101 -> ue: 0, 1, 2, 3, 4
      final reader = BitReader(Uint8List.fromList([0xa6, 0x42, 0x80]));
      expect([for (var i = 0; i < 5; i++) reader.readUe()], [0, 1, 2, 3, 4]);
    });

    test('maps signed Exp-Golomb codes', () {
      // codeNum 1, 2, 3, 4 -> 1, -1, 2, -2
      final reader = BitReader(Uint8List.fromList([0x4c, 0x85]));
      expect([for (var i = 0; i < 4; i++) reader.readSe()], [1, -1, 2, -2]);
    });

    test('throws at end of data', () {
      final reader = BitReader(Uint8List.fromList([0x00]));
      expect(reader.readUe, throwsFormatException);
    });
  });

  test('removeEmulationPrevention strips 0x03 after two zero bytes', () {
    final rbsp = removeEmulationPrevention(
      Uint8List.fromList([1, 0, 0, 3, 1, 0, 0, 3, 0, 9]),
    );
    expect(rbsp, [1, 0, 0, 1, 0, 0, 0, 9]);
  });

  group('AnnexBSplitter', () {
    test('produces the same NAL units regardless of chunking', () {
      final data = loadFixture();
      List<int> typesFor(List<Uint8List> chunks) {
        final splitter = AnnexBSplitter();
        return [
          for (final chunk in chunks) ...splitter.add(chunk).map((n) => n.type),
          ...splitter.flush().map((n) => n.type),
        ];
      }

      final whole = typesFor([data]);
      expect(whole, isNotEmpty);
      expect(typesFor(randomChunks(data, seed: 7)), whole);
      expect(typesFor(randomChunks(data, seed: 9, maxChunk: 3)), whole);
    });

    test('handles 3- and 4-byte start codes split across chunks', () {
      final splitter = AnnexBSplitter();
      final nals = [
        ...splitter.add(Uint8List.fromList([0xff, 0x00, 0x00])),
        ...splitter.add(Uint8List.fromList([0x00, 0x01, 0x67, 0xaa, 0x00])),
        ...splitter.add(Uint8List.fromList([0x00, 0x01, 0x68, 0xbb])),
        ...splitter.flush(),
      ];
      expect(nals.map((n) => n.bytes.toList()), [
        [0x67, 0xaa],
        [0x68, 0xbb],
      ]);
    });
  });

  group('AccessUnitAssembler', () {
    test('groups the fixture into one access unit per frame', () {
      final units = fixtureAccessUnits();
      expect(units, hasLength(60));
      expect(units.where((u) => u.isKeyframe), hasLength(2));
      expect(units.first.isKeyframe, isTrue);
      expect(units.first.firstOfType(NalUnitType.sps), isNotNull);
      expect(units.every((u) => u.hasPicture), isTrue);
    });

    test(
      'splits on access unit delimiters and keeps parameter sets as prefix',
      () {
        NalUnit nal(List<int> bytes) => NalUnit(Uint8List.fromList(bytes));
        final assembler = AccessUnitAssembler();
        final out = [
          assembler.add(nal([0x09, 0x10])), // AUD
          assembler.add(nal([0x67, 0x64])), // SPS
          assembler.add(nal([0x68, 0xee])), // PPS
          assembler.add(nal([0x65, 0x88])), // IDR, first_mb = 0
          assembler.add(nal([0x09, 0x30])), // AUD -> completes frame 1
          assembler.add(nal([0x41, 0x9a])), // P slice
        ].whereType<AccessUnit>().toList();
        expect(out, hasLength(1));
        expect(out.single.nalUnits.map((n) => n.type), [9, 7, 8, 5]);
        expect(assembler.flush()!.nalUnits.map((n) => n.type), [9, 1]);
      },
    );

    test('serialises AVCC without parameter sets', () {
      final unit = fixtureAccessUnits().first;
      final avcc = unit.toAvcc();
      final view = ByteData.sublistView(avcc);
      var offset = 0;
      final types = <int>[];
      while (offset < avcc.length) {
        final length = view.getUint32(offset);
        types.add(avcc[offset + 4] & 0x1f);
        offset += 4 + length;
      }
      expect(offset, avcc.length);
      expect(types, isNot(contains(NalUnitType.sps)));
      expect(types, contains(NalUnitType.sliceIdr));
    });
  });

  group('SpsInfo', () {
    test('parses dimensions, profile and frame rate', () {
      final sps = fixtureAccessUnits().first.firstOfType(NalUnitType.sps)!;
      final info = SpsInfo.parse(sps);
      expect(info.width, 320);
      expect(info.height, 240);
      expect(info.profileIdc, 100);
      expect(info.profileName, 'High');
      expect(info.frameRate, closeTo(30, 0.01));
      expect(info.codecString, startsWith('avc1.64'));
      expect(info.codecString, hasLength(11));
    });

    test('rejects other NAL types', () {
      expect(
        () => SpsInfo.parse(NalUnit(Uint8List.fromList([0x68, 0x00]))),
        throwsFormatException,
      );
    });
  });
}
