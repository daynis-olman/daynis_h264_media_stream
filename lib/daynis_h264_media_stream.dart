/// Live H.264 video streaming for Flutter web.
///
/// Plays H.264 Annex-B video delivered over HTTP — either
/// `multipart/x-mixed-replace` (one or more NAL units per part, as served by
/// embedded cameras) or a raw byte stream — using WebCodecs or Media Source
/// Extensions. Demuxing, H.264 parsing and MP4 muxing are written in Dart,
/// so no JavaScript library is needed.
///
/// Start with [H264StreamController] and [H264StreamView]. The parsing
/// building blocks ([H264StreamParser], [MultipartDemuxer], [Fmp4Muxer],
/// [SpsInfo]) are pure Dart and usable on any platform; [connectMultipart]
/// reads companion multipart streams such as JSON telemetry.
library;

export 'codec.dart';
export 'src/player/h264_stream_controller.dart' show H264StreamController;
export 'src/player/h264_stream_options.dart'
    show H264Backend, H264StreamOptions, H264StreamState, H264StreamStats;
export 'src/player/h264_stream_view.dart'
    show H264StreamView, H264StreamWidgetBuilder;
