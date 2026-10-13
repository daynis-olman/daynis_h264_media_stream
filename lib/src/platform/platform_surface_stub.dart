import '../player/h264_stream_options.dart';
import 'video_renderer.dart';

/// Creates the surface for the current platform.
PlatformSurface createPlatformSurface() => _UnsupportedSurface();

class _UnsupportedSurface implements PlatformSurface {
  @override
  bool get isSupported => false;

  @override
  H264Backend? resolveBackend(H264Backend requested) => null;

  @override
  VideoRenderer createRenderer(
    H264Backend backend, {
    required Duration maxLatency,
    required void Function(Object error) onError,
    required void Function() onFrame,
  }) => throw UnsupportedError('H.264 playback is only supported on the web');

  @override
  Stream<bool> get visibilityChanges => const Stream.empty();

  @override
  Object? get hostElement => null;

  @override
  void dispose() {}
}
