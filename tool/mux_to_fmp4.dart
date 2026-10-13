// Muxes an Annex-B H.264 file into fragmented MP4 using the package's own
// muxer, for checking output with ffprobe or a browser:
//
//   dart run tool/mux_to_fmp4.dart input.h264 output.mp4
import 'dart:io';
import 'dart:typed_data';

import 'package:daynis_h264_media_stream/codec.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'usage: dart run tool/mux_to_fmp4.dart <input.h264> <output.mp4>',
    );
    exit(64);
  }
  final parser = H264StreamParser();
  final units = [
    ...parser.add(File(args[0]).readAsBytesSync()),
    ...parser.close(),
  ];
  final muxer = Fmp4Muxer(sps: parser.sps!, pps: parser.pps!);
  final fps = parser.spsInfo!.frameRate ?? 30;
  final duration = (muxer.timescale / fps).round();
  final out = BytesBuilder()..add(muxer.initSegment());
  var time = 0;
  for (final unit in units) {
    out.add(
      muxer.mediaSegment([
        Fmp4Sample.fromAccessUnit(unit, duration: duration),
      ], baseMediaDecodeTime: time),
    );
    time += duration;
  }
  File(args[1]).writeAsBytesSync(out.takeBytes());
  stdout.writeln('${parser.spsInfo}: ${units.length} frames -> ${args[1]}');
}
