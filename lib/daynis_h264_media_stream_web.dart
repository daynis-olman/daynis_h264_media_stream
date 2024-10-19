import 'dart:html' as html;
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:js/js.dart';

@JS('JMuxer')
class JMuxer {
  external factory JMuxer(dynamic config);
  external void feed(dynamic data);
}

class DaynisH264MediaStreamPlugin {
  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
      'daynis_h264_media_stream',
      const StandardMethodCodec(),
    );

    channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'playVideo') {
        final String? videoUrl = call.arguments as String?;

        if (videoUrl == null || !videoUrl.startsWith('http')) {
          return PlatformException(
            code: 'invalid_url',
            message: 'Invalid or null video URL.',
          );
        }

        try {
          final jmuxer = await loadJmuxer();

          if (jmuxer == null) {
            throw Exception('JMuxer function not found.');
          }

          final videoElement = html.VideoElement()
            ..autoplay = true
            ..controls = true;

          html.document.body?.children?.add(videoElement);

          final jmuxerInstance = JMuxer({
            'node': videoElement,
            'mode': 'video',
            'flushingTime': 0,
            'fps': 30,
          });

          return Future.value();
        } catch (e) {
          return PlatformException(
            code: 'js_error',
            message: 'Error loading or calling JMuxer: $e',
          );
        }
      }
      return Future.value();
    });
  }

  static Future<JMuxer?> loadJmuxer() async {
    final script = html.ScriptElement()
      ..type = 'application/javascript'
      ..src = 'assets/jmuxer.js';

    final completer = Completer<JMuxer?>();

    script.onLoad.listen((_) {
      try {
        final jmuxer = JMuxer({
          'node': html.document.createElement('video'),
          'mode': 'video',
          'flushingTime': 0,
          'fps': 30,
        });
        completer.complete(jmuxer);
      } catch (e) {
        completer.completeError(e);
      }
    });

    html.document.head?.append(script);

    return completer.future;
  }
}