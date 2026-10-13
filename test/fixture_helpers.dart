import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:daynis_h264_media_stream/daynis_h264_media_stream.dart';

/// 2 s of 320x240 @ 30 fps High-profile H.264 (testsrc2), keyframe every
/// 30 frames, SPS/PPS repeated on each keyframe.
Uint8List loadFixture() =>
    File('test/fixtures/testsrc_320x240_30fps.h264').readAsBytesSync();

/// Splits [data] into chunks of pseudo-random sizes in [1, maxChunk].
List<Uint8List> randomChunks(
  Uint8List data, {
  int seed = 1,
  int maxChunk = 512,
}) {
  final rng = Random(seed);
  final chunks = <Uint8List>[];
  var offset = 0;
  while (offset < data.length) {
    final size = min(1 + rng.nextInt(maxChunk), data.length - offset);
    chunks.add(Uint8List.sublistView(data, offset, offset + size));
    offset += size;
  }
  return chunks;
}

/// Parses the fixture into access units in one go.
List<AccessUnit> fixtureAccessUnits() {
  final parser = H264StreamParser();
  return [...parser.add(loadFixture()), ...parser.close()];
}

/// Wraps each access unit in a multipart/x-mixed-replace part, the way an
/// embedded camera serves `/video-frame`.
Uint8List buildMultipart(
  List<AccessUnit> units, {
  String boundary = 'frame',
  bool contentLength = true,
  String eol = '\r\n',
}) {
  final out = BytesBuilder();
  for (final unit in units) {
    final body = unit.toAnnexB();
    out.add(
      ascii.encode(
        '--$boundary${eol}Content-Type: application/octet-stream$eol',
      ),
    );
    if (contentLength) {
      out.add(ascii.encode('Content-Length: ${body.length}$eol'));
    }
    out.add(ascii.encode(eol));
    out.add(body);
    out.add(ascii.encode(eol));
  }
  return out.takeBytes();
}
