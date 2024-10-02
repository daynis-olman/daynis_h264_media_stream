import 'package:flutter/material.dart';
import 'package:daynis_h264_media_stream/daynis_h264_media_stream.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Replace with the actual URL for your H264 stream
    String streamUrl = 'h264-stream-url';

    // Initialie H264 stream
    initializeH264Stream(streamUrl);

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: Text('H264 Media Stream Test'),
        ),
        body: Center(
          child: Text('Streaming H264 Video...'),
        ),
      ),
    );
  }
}