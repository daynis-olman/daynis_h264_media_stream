import '../h264/access_unit.dart';
import '../h264/nal_unit.dart';
import '../h264/sps.dart';
import '../player/h264_stream_options.dart';

/// Renders decoded H.264 access units on a platform surface.
abstract interface class VideoRenderer {
  /// The decoding strategy this renderer implements.
  H264Backend get backend;

  /// Prepares the decoder for a stream described by [sps] and [pps].
  /// Throws an `H264StreamException` if the stream is not supported.
  Future<void> configure(SpsInfo info, NalUnit sps, NalUnit pps);

  /// Queues [unit] for decoding. [duration] is the nominal display time.
  /// Returns `false` if the unit was dropped.
  bool decode(AccessUnit unit, Duration duration);

  /// Drops frames until the next keyframe (e.g. after a reconnect).
  void requireKeyframe();

  /// Releases decoder resources and detaches the rendering element.
  void dispose();
}

/// Platform services used by the controller and the view.
abstract interface class PlatformSurface {
  /// Whether H.264 playback is available on this platform.
  bool get isSupported;

  /// The backend that [H264Backend.auto] resolves to, or `null` if none is
  /// available.
  H264Backend? resolveBackend(H264Backend requested);

  /// Creates a renderer for [backend] that reports asynchronous decoder
  /// failures to [onError].
  VideoRenderer createRenderer(
    H264Backend backend, {
    required Duration maxLatency,
    required void Function(Object error) onError,
    required void Function() onFrame,
  });

  /// Emits `true` when the page becomes visible and `false` when hidden.
  Stream<bool> get visibilityChanges;

  /// The platform element hosting the video (web: an `HTMLDivElement`).
  Object? get hostElement;

  /// Releases platform resources.
  void dispose();
}
