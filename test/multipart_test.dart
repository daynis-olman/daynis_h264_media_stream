import 'dart:convert';
import 'dart:typed_data';

import 'package:daynis_h264_media_stream/daynis_h264_media_stream.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture_helpers.dart';

void main() {
  group('multipartBoundary', () {
    test('extracts plain and quoted boundaries', () {
      expect(
        multipartBoundary('multipart/x-mixed-replace; boundary=frame'),
        'frame',
      );
      expect(
        multipartBoundary('multipart/x-mixed-replace;boundary="message"'),
        'message',
      );
      expect(
        multipartBoundary('Multipart/Mixed; charset=utf-8; BOUNDARY=abc'),
        'abc',
      );
    });

    test('returns null for non-multipart content', () {
      expect(multipartBoundary('video/h264'), isNull);
      expect(multipartBoundary(null), isNull);
      expect(multipartBoundary('multipart/x-mixed-replace'), isNull);
    });
  });

  group('MultipartDemuxer', () {
    final units = fixtureAccessUnits();

    for (final contentLength in [true, false]) {
      for (final eol in ['\r\n', '\n']) {
        test(
          'recovers every part (Content-Length: $contentLength, EOL: ${jsonEncode(eol)})',
          () {
            final stream = buildMultipart(
              units,
              contentLength: contentLength,
              eol: eol,
            );
            final demuxer = MultipartDemuxer('frame');
            final parts = [
              for (final chunk in randomChunks(stream, seed: 3))
                ...demuxer.add(chunk),
            ];
            // Without Content-Length the final part completes with the next
            // boundary, which a live stream sends with the following frame.
            final expected = contentLength ? units.length : units.length - 1;
            expect(parts, hasLength(expected));
            for (var i = 0; i < expected; i++) {
              expect(parts[i].body, units[i].toAnnexB());
            }
            expect(parts.first.contentType, 'application/octet-stream');
          },
        );
      }
    }

    test('parses JSON telemetry parts and the closing boundary', () {
      const body =
          '--message\r\nContent-Type: application/json\r\n\r\n{"yaw": 12.5}\r\n'
          '--message\r\nContent-Type: application/json\r\n\r\n{"yaw": 13}\r\n--message--\r\n';
      final demuxer = MultipartDemuxer('message');
      final parts = demuxer.add(Uint8List.fromList(utf8.encode(body)));
      expect(parts.map((p) => p.json), [
        {'yaw': 12.5},
        {'yaw': 13},
      ]);
      expect(demuxer.isClosed, isTrue);
    });

    test('ignores delimiter bytes that do not start a line', () {
      final demuxer = MultipartDemuxer('frame');
      final parts = demuxer.add(
        Uint8List.fromList(
          utf8.encode(
            '--frame\r\n\r\nabc--framexyz\r\n--frame\r\n\r\nnext\r\n--frame\r\n',
          ),
        ),
      );
      expect(parts.map((p) => p.text), ['abc--framexyz', 'next']);
    });
  });

  group('H264StreamParser', () {
    test('parses multipart and raw streams identically', () {
      final units = fixtureAccessUnits();
      final multipart = H264StreamParser(
        contentType: 'multipart/x-mixed-replace; boundary=frame',
      );
      final fromMultipart = [
        for (final chunk in randomChunks(buildMultipart(units), seed: 5))
          ...multipart.add(chunk),
        ...multipart.close(),
      ];
      final raw = H264StreamParser(contentType: 'application/octet-stream');
      final fromRaw = [
        for (final chunk in randomChunks(loadFixture(), seed: 6))
          ...raw.add(chunk),
        ...raw.close(),
      ];
      expect(multipart.isMultipart, isTrue);
      expect(raw.isMultipart, isFalse);
      expect(
        fromMultipart.map((u) => u.toAnnexB()),
        fromRaw.map((u) => u.toAnnexB()),
      );
      expect(raw.spsInfo!.width, 320);
      expect(raw.pps, isNotNull);
    });
  });
}
