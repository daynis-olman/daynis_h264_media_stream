# daynis_h264_media_stream example

Plays a live multipart H.264 stream and its JSON telemetry.

From the package root, start the test server, then run the app:

```sh
dart run tool/stream_server.dart --file my_clip.mp4 --port 8080
cd example && flutter run -d chrome
```

Deep links: `?url=http://localhost:8080/video-frame&backend=mediaSource&autoplay=1`.
