@JS()
library daynis_h264_media_stream;

import 'dart:html';
import 'dart:typed_data'; // For Uint8List and ByteBuffer
import 'package:js/js.dart';

// Define JMuxerOptions to pass as options to the JMuxer object
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

// Define JMuxerFeedData to pass video chunks
@JS()
@anonymous
class JMuxerFeedData {
  external factory JMuxerFeedData({required Uint8List video});
}

// External JMuxer class to use in Dart code
@JS('JMuxer')
class JMuxer {
  external JMuxer(JMuxerOptions options);
  external void feed(JMuxerFeedData data);
}

// Function to initialize the H264 stream in the video player
void initializeH264Stream(String streamUrl) {
  final videoElement = VideoElement()
    ..id = 'videoPlayer'
    ..controls = true
    ..autoplay = true;

  // Append the video element to the body
  document.body?.append(videoElement);

  // Initialize JMuxer with options
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

    // Convert the response into Uint8List to be fed into JMuxer
    final reader = (response.response as ByteBuffer).asUint8List();
    jmuxer.feed(JMuxerFeedData(video: reader));
  } catch (error) {
    print('Error fetching video frames: $error');
  }
}