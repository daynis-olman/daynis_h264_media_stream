## 1.0.1

Rewritten from scratch. Replaces the `DaynisH264MediaStream.playVideo` API.

- Adds `H264StreamController` and `H264StreamView` for live H.264 over HTTP,
  either multipart or raw Annex-B.
- Decodes with WebCodecs in secure contexts and Media Source Extensions
  (including `ManagedMediaSource`) elsewhere. Falls back automatically.
- Adds live-edge latency control, stall detection, reconnect with backoff and
  pausing while the page is hidden.
- Adds `connectMultipart` for companion telemetry streams.
- Adds a pure-Dart `codec.dart` library: `H264StreamParser`,
  `MultipartDemuxer`, `SpsInfo` and `Fmp4Muxer`.
- Removes JMuxer, `package:js` and `dart:html`. Uses `dart:js_interop` and
  `package:web`, and compiles to WebAssembly.
- Requires Dart 3.8 / Flutter 3.32 or later.
- Relicensed under MIT.

## 0.0.1

- Initial release.
