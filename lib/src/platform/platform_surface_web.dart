import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../player/h264_stream_options.dart';
import 'mse_renderer.dart';
import 'video_renderer.dart';
import 'webcodecs_renderer.dart';

/// Creates the surface for the current platform.
PlatformSurface createPlatformSurface() => WebSurface();

/// Browser implementation: owns a host `<div>` that the view embeds and that
/// renderers draw into, so resizing or re-parenting the Flutter widget never
/// restarts the stream.
class WebSurface implements PlatformSurface {
  /// Creates the host element.
  WebSurface() {
    final style = host.style;
    style.width = '100%';
    style.height = '100%';
    style.position = 'relative';
    style.overflow = 'hidden';
    style.pointerEvents = 'none';
    style.backgroundColor = 'transparent';
  }

  /// The element embedded by the view.
  final web.HTMLDivElement host = web.HTMLDivElement();

  static bool get _hasWebCodecs =>
      web.window.isSecureContext && globalContextHas('VideoDecoder');

  static bool get _hasMediaSource =>
      globalContextHas('MediaSource') || globalContextHas('ManagedMediaSource');

  @override
  bool get isSupported => _hasWebCodecs || _hasMediaSource;

  @override
  H264Backend? resolveBackend(H264Backend requested) => switch (requested) {
    H264Backend.auto =>
      _hasWebCodecs
          ? H264Backend.webCodecs
          : (_hasMediaSource ? H264Backend.mediaSource : null),
    H264Backend.webCodecs => _hasWebCodecs ? H264Backend.webCodecs : null,
    H264Backend.mediaSource => _hasMediaSource ? H264Backend.mediaSource : null,
  };

  @override
  VideoRenderer createRenderer(
    H264Backend backend, {
    required Duration maxLatency,
    required void Function(Object error) onError,
    required void Function() onFrame,
  }) {
    if (backend == H264Backend.webCodecs) {
      final renderer = WebCodecsRenderer(onError: onError, onFrame: onFrame);
      host.replaceChildren(renderer.element);
      return renderer;
    }
    final renderer = MseRenderer(
      maxLatency: maxLatency,
      onError: onError,
      onFrame: onFrame,
    );
    host.replaceChildren(renderer.element);
    return renderer;
  }

  @override
  Stream<bool> get visibilityChanges =>
      const web.EventStreamProvider<web.Event>('visibilitychange')
          .forTarget(web.document)
          .map((_) => web.document.visibilityState != 'hidden');

  @override
  Object? get hostElement => host;

  @override
  void dispose() => host.remove();
}

/// Whether the global object has a property named [name].
bool globalContextHas(String name) => globalContext.has(name);
