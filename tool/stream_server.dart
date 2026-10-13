// A local test server that streams H.264 the way embedded cameras do:
// `multipart/x-mixed-replace; boundary=frame`, one access unit per part,
// paced in real time and looped forever.
//
//   dart run tool/stream_server.dart [--file video.h264|video.mp4] [--port 8080] [--raw]
//
// Endpoints (CORS enabled):
//   GET /video-frame   multipart H.264 (or raw Annex-B with --raw)
//   GET /head-pose     multipart JSON telemetry at 10 Hz (boundary=message)
//
// MP4 input is converted to Annex-B with ffmpeg, which must be on PATH.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:daynis_h264_media_stream/codec.dart';

Future<void> main(List<String> args) async {
  var file = 'test/fixtures/testsrc_320x240_30fps.h264';
  var port = 8080;
  var raw = false;
  double? fpsOverride;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--file':
        file = args[++i];
      case '--port':
        port = int.parse(args[++i]);
      case '--fps':
        fpsOverride = double.parse(args[++i]);
      case '--raw':
        raw = true;
      default:
        stderr.writeln('Unknown argument ${args[i]}');
        exit(64);
    }
  }

  final annexB = await _loadAnnexB(file);
  final parser = H264StreamParser();
  final units = [...parser.add(annexB), ...parser.close()];
  final info = parser.spsInfo;
  if (units.isEmpty || info == null) {
    stderr.writeln('No H.264 access units with an SPS found in $file');
    exit(65);
  }
  final firstKey = units.indexWhere((u) => u.isKeyframe);
  final frames = [
    for (var i = 0; i < units.length; i++)
      // Repeat SPS/PPS on every keyframe so any client can join mid-stream.
      units[i].isKeyframe && units[i].firstOfType(NalUnitType.sps) == null
          ? units[i].toAnnexB(prepend: [parser.sps!, parser.pps!])
          : units[i].toAnnexB(),
  ];
  final keyframes = [
    for (var i = 0; i < units.length; i++)
      if (units[i].isKeyframe) i,
  ];
  final fps = fpsOverride ?? info.frameRate ?? 30;
  final interval = Duration(microseconds: (1e6 / fps).round());

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout
    ..writeln(
      'Streaming $file ($info, ${units.length} frames, ${fps.toStringAsFixed(1)} fps)',
    )
    ..writeln(
      '  http://localhost:$port/video-frame  ${raw ? 'raw Annex-B' : 'multipart, boundary=frame'}',
    )
    ..writeln(
      '  http://localhost:$port/head-pose    multipart JSON, boundary=message',
    );

  final clock = Stopwatch()..start();
  await for (final request in server) {
    request.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Cache-Control', 'no-store');
    switch (request.uri.path) {
      case '/video-frame':
        // Start each client at the keyframe nearest to "now" on the loop.
        final now =
            (clock.elapsedMicroseconds / interval.inMicroseconds).floor() %
            frames.length;
        final start = keyframes.lastWhere(
          (k) => k <= now,
          orElse: () => firstKey,
        );
        unawaited(_streamVideo(request.response, frames, start, interval, raw));
      case '/head-pose':
        unawaited(_streamHeadPose(request.response, clock));
      default:
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Try /video-frame or /head-pose');
        await request.response.close();
    }
  }
}

Future<void> _streamVideo(
  HttpResponse response,
  List<Uint8List> frames,
  int start,
  Duration interval,
  bool raw,
) async {
  response.bufferOutput = false;
  response.headers.contentType = raw
      ? ContentType('video', 'h264')
      : ContentType(
          'multipart',
          'x-mixed-replace',
          parameters: {'boundary': 'frame'},
        );
  final pace = Stopwatch()..start();
  var index = start;
  var sent = 0;
  try {
    while (true) {
      final frame = frames[index];
      if (!raw) {
        response.add(
          ascii.encode(
            '--frame\r\nContent-Type: application/octet-stream\r\n'
            'Content-Length: ${frame.length}\r\n\r\n',
          ),
        );
      }
      response.add(frame);
      if (!raw) response.add(const [13, 10]);
      await response.flush();
      index = (index + 1) % frames.length;
      sent++;
      final due = interval * sent - pace.elapsed;
      if (due > Duration.zero) await Future<void>.delayed(due);
    }
  } catch (_) {
    // Client disconnected.
  }
}

Future<void> _streamHeadPose(HttpResponse response, Stopwatch clock) async {
  response.bufferOutput = false;
  response.headers.contentType = ContentType(
    'multipart',
    'x-mixed-replace',
    parameters: {'boundary': 'message'},
  );
  try {
    while (true) {
      final t = clock.elapsedMilliseconds / 1000;
      final pose = {
        'head_yaw_deg': double.parse(
          (18 + 6 * sin(t * 0.7)).toStringAsFixed(2),
        ),
        'head_pitch_deg': double.parse(
          (12 + 4 * sin(t * 0.9 + 1)).toStringAsFixed(2),
        ),
        'head_roll_deg': double.parse((2 * sin(t * 0.5)).toStringAsFixed(2)),
        'distance': double.parse(
          (0.75 + 0.2 * sin(t * 0.3)).toStringAsFixed(3),
        ),
        'tracking': (t % 20) < 17 ? 'true' : 'false',
      };
      response.add(
        utf8.encode(
          '--message\r\nContent-Type: application/json\r\n\r\n${jsonEncode(pose)}\r\n',
        ),
      );
      await response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  } catch (_) {
    // Client disconnected.
  }
}

Future<Uint8List> _loadAnnexB(String path) async {
  if (!path.toLowerCase().endsWith('.mp4')) return File(path).readAsBytesSync();
  final temp = await Directory.systemTemp.createTemp('h264_stream');
  final out = '${temp.path}/stream.h264';
  final result = await Process.run('ffmpeg', [
    '-v', 'error', '-y', '-i', path, //
    '-an', '-c:v', 'copy', '-bsf:v', 'h264_mp4toannexb', '-f', 'h264', out,
  ]);
  if (result.exitCode != 0) {
    stderr.writeln('ffmpeg failed to convert $path:\n${result.stderr}');
    exit(66);
  }
  return File(out).readAsBytesSync();
}
