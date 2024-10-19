import 'package:flutter/material.dart';
import 'package:daynis_h264_media_stream/daynis_h264_media_stream.dart'; // Make sure this is correct

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('H264 Stream Example')),
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final videoUrl = 'YOUR_H264_STREAM_URL';
              try {
                await DaynisH264MediaStream.playVideo(videoUrl); // Make sure DaynisH264MediaStream exists
                print('Video started playing.');
              } catch (e) {
                print('Error playing video: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error playing video: $e')),
                );
              }
            },
            child: Text('Play Video'),
          ),
        ),
      ),
    );
  }
}