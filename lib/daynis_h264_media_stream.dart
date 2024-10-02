@JS()
library daynis_h264_media_stream;

import 'dart:html';
import 'package:js/js.dart';

// Initialize JMuxer in Dart
void initializeH264Stream(String streamUrl) {
  final videoElement = VideoElement()
    ..id = 'videoPlayer'
    ..controls = true
    ..autoplay = true;

  document.body?.append(videoElement);

  final jmuxer = JMuxer(JMuxerOptions(
    node: '#videoPlayer',
    mode: 'video',
    fps: 30,
    flushingTime: 100,
  ));

  _fetchAndStreamH264(jmuxer, streamUrl);
}

// Function to fetch and stream raw H264 data
void _fetchAndStreamH264(JMuxer jmuxer, String streamUrl) async {
  try {
    final response = await HttpRequest.request(
      streamUrl,
      method: 'GET',
      responseType: 'arraybuffer',
    );

    // Stream the fetched H264 data to JMuxer
    final reader = (response.response as ByteBuffer).asUint8List();
    jmuxer.feed(JMuxerFeedData(video: reader));
  } catch (error) {
    print('Error fetching video frames: $error');
  }
}

@JS('JMuxer')
class JMuxer {
  external JMuxer(JMuxerOptions options);
  external void feed(JMuxerFeedData data);
}

@JS()
@anonymous
class JMuxerOptions {
  external factory JMuxerOptions({
    required String node,
    required String mode,
    required int fps,
    required int flushingTime,
  });
}

@JS()
@anonymous
class JMuxerFeedData {
  external factory JMuxerFeedData({required Uint8List video});
}