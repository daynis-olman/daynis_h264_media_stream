# daynis_h264_media_stream

[![pub package](https://img.shields.io/pub/v/daynis_h264_media_stream.svg)](https://pub.dev/packages/daynis_h264_media_stream)

Live H.264 video over HTTP for Flutter web. Plays the
`multipart/x-mixed-replace` streams served by IP cameras and embedded devices,
or raw Annex-B streams. Written in Dart, with no bundled JavaScript.

![Example app playing a multipart H.264 stream](https://raw.githubusercontent.com/daynis-olman/daynis_h264_media_stream/main/doc/screenshot.png)

## Features

- Decodes with **WebCodecs** in secure contexts (HTTPS, `localhost`).
  Elsewhere it uses **Media Source Extensions**: plain `http://` origins such
  as a web app served by the device itself, and iPhone Safari via
  `ManagedMediaSource`.
- Stays close to the live edge, and reconnects with backoff when the stream
  ends, stalls or errors.
- Copes with parts with or without `Content-Length`, CRLF or LF line endings,
  and NAL units split across parts.
- The video sits under ordinary Flutter widgets and never captures gestures.
  Resizing or moving the view doesn't reconnect.
- `connectMultipart` reads companion multipart streams, such as JSON
  telemetry.
- `codec.dart` holds the parser, SPS reader and fragmented MP4 muxer, with no
  Flutter dependency.
- Compiles to JavaScript and WebAssembly.

## Usage

```dart
import 'package:daynis_h264_media_stream/daynis_h264_media_stream.dart';

final controller = H264StreamController(
  uri: Uri.base.resolve('/camera/video-frame'),
)..start();

// In build():
H264StreamView(
  controller: controller,
  placeholderBuilder: (context, c) => Center(child: Text('${c.state.name}…')),
);

// When finished:
controller.dispose();
```

The controller is a `ChangeNotifier`. It exposes:

- `state`: `connecting`, `waitingForKeyframe`, `playing`, `reconnecting`,
  `paused` or `error`.
- `videoInfo`: resolution, profile and frame rate.
- `backend`: the decoder in use.
- `stats`: frame rate, bitrate, dropped frames and reconnects.

Behaviour is tuned with `H264StreamOptions`:

```dart
H264StreamController(
  uri: uri,
  options: const H264StreamOptions(
    backend: H264Backend.auto, // or webCodecs, mediaSource
    maxLatency: Duration(milliseconds: 300),
    stallTimeout: Duration(seconds: 4),
    pauseWhenHidden: true,
  ),
);
```

Reading a telemetry stream:

```dart
final subscription = connectMultipart(Uri.base.resolve('/camera/head-pose'))
    .listen((part) => print(part.json));
```

## Stream format

```text
Content-Type: multipart/x-mixed-replace; boundary=frame

--frame
Content-Type: application/octet-stream
Content-Length: 4127

<Annex-B NAL units: AUD, SPS, PPS, IDR or P slices>
--frame
...
```

A response that isn't multipart is read as raw Annex-B. Parts don't need to
line up with frames.

## Local testing

`tool/stream_server.dart` streams an `.h264` file, or an `.mp4` (converted with
ffmpeg), the same way a camera does:

```sh
dart run tool/stream_server.dart --file clip.mp4 --port 8080
cd example && flutter run -d chrome
```

## Limitations

- **Web only.** On other platforms `isSupported` is false, but `codec.dart`
  works everywhere.
- **Video only, no B-frames.** That suits live camera encoders.
- **One view at a time.** A controller can only be shown in one
  `H264StreamView` at once.
- **Cross-origin streams.** They need CORS headers. HTTPS pages can't load
  `http://` streams (mixed content).

## Licence

MIT
