import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../h264/access_unit.dart';
import '../h264/nal_unit.dart';
import '../h264/sps.dart';
import '../mp4/fmp4_muxer.dart';
import '../player/h264_stream_options.dart';
import '../transport/byte_stream.dart';
import 'video_renderer.dart';

/// Plays the stream through Media Source Extensions: access units are muxed
/// to fragmented MP4 in Dart and appended to a `SourceBuffer` behind a muted
/// `<video>` element. Playback is kept close to the live edge.
class MseRenderer implements VideoRenderer {
  /// Creates the renderer and its video element.
  MseRenderer({
    required Duration maxLatency,
    required void Function(Object error) onError,
    required void Function() onFrame,
  }) : _maxLatency = maxLatency.inMicroseconds / Duration.microsecondsPerSecond,
       _onError = onError,
       _onFrame = onFrame {
    element
      ..muted = true
      ..autoplay = true
      ..playsInline = true
      ..controls = false
      ..disablePictureInPicture = true;
    // Required by ManagedMediaSource on Safari, and avoids casting UI.
    (element as JSObject).setProperty('disableRemotePlayback'.toJS, true.toJS);
    final style = element.style;
    style.width = '100%';
    style.height = '100%';
    style.objectFit = 'contain';
    style.display = 'block';
  }

  /// The video element the stream plays in.
  final web.HTMLVideoElement element = web.HTMLVideoElement();
  final double _maxLatency;
  final void Function(Object error) _onError;
  final void Function() _onFrame;

  /// Segments waiting to be appended before delta frames are dropped.
  static const int maxQueuedSegments = 30;

  static const int _timescale = 90000;

  web.MediaSource? _mediaSource;
  web.SourceBuffer? _sourceBuffer;
  String? _objectUrl;
  Fmp4Muxer? _muxer;
  final List<Uint8List> _queue = [];
  int _decodeTime = 0;
  bool _needKeyframe = true;
  bool _disposed = false;
  Timer? _liveEdgeTimer;
  int _ticks = 0;
  StreamSubscription<web.Event>? _updateEnd;
  StreamSubscription<web.Event>? _frameEvents;

  @override
  H264Backend get backend => H264Backend.mediaSource;

  @override
  Future<void> configure(SpsInfo info, NalUnit sps, NalUnit pps) async {
    final muxer = Fmp4Muxer(sps: sps, pps: pps, timescale: _timescale);
    if (!_isTypeSupported(muxer.mimeType)) {
      throw H264StreamException(
        'Media Source Extensions cannot play ${muxer.mimeType}',
      );
    }
    _teardownSource();
    final mediaSource = _createMediaSource();
    final opened = const web.EventStreamProvider<web.Event>(
      'sourceopen',
    ).forTarget(mediaSource).first;
    final url = web.URL.createObjectURL(mediaSource);
    _objectUrl = url;
    element.src = url;
    await opened.timeout(
      const Duration(seconds: 5),
      onTimeout: () =>
          throw const H264StreamException('MediaSource did not open'),
    );
    if (_disposed) return;
    final buffer = mediaSource.addSourceBuffer(muxer.mimeType);
    buffer.mode = 'segments';
    _updateEnd = const web.EventStreamProvider<web.Event>(
      'updateend',
    ).forTarget(buffer).listen((_) => _pump());
    _frameEvents ??= web.EventStreamProviders.timeUpdateEvent
        .forTarget(element)
        .listen((_) => _onFrame());
    _mediaSource = mediaSource;
    _sourceBuffer = buffer;
    _muxer = muxer;
    _decodeTime = 0;
    _needKeyframe = true;
    _queue
      ..clear()
      ..add(muxer.initSegment());
    _pump();
    _liveEdgeTimer ??= Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _keepLive(),
    );
  }

  @override
  bool decode(AccessUnit unit, Duration duration) {
    final muxer = _muxer;
    if (muxer == null) return false;
    final key = unit.isKeyframe;
    if (!key && (_needKeyframe || _queue.length > maxQueuedSegments)) {
      _needKeyframe = true;
      return false;
    }
    if (key && _queue.length > maxQueuedSegments) {
      // Backlog: the init segment was appended first, so everything queued is
      // stale media that a fresh keyframe supersedes.
      _queue.clear();
    }
    final ticks =
        (duration.inMicroseconds * _timescale / Duration.microsecondsPerSecond)
            .round()
            .clamp(1, _timescale);
    _queue.add(
      muxer.mediaSegment([
        Fmp4Sample.fromAccessUnit(unit, duration: ticks),
      ], baseMediaDecodeTime: _decodeTime),
    );
    _decodeTime += ticks;
    _needKeyframe = false;
    _pump();
    return true;
  }

  @override
  void requireKeyframe() => _needKeyframe = true;

  void _pump() {
    final buffer = _sourceBuffer;
    if (_disposed || buffer == null || buffer.updating || _queue.isEmpty) {
      return;
    }
    final segment = _queue.removeAt(0);
    try {
      buffer.appendBuffer(segment.toJS);
    } catch (e) {
      // QuotaExceededError or a closed source: free space and wait for a
      // fresh keyframe rather than corrupting the timeline.
      _queue.clear();
      _needKeyframe = true;
      _prune(force: true);
      if (_mediaSource?.readyState != 'open') {
        _onError(H264StreamException('Media source closed', cause: e));
      }
    }
  }

  void _keepLive() {
    final buffered = element.buffered;
    if (buffered.length == 0) return;
    final start = buffered.start(0);
    final end = buffered.end(buffered.length - 1);
    final current = element.currentTime;
    final lag = end - current;
    if (current < start || lag > _maxLatency) {
      element.currentTime = end - 0.02 < start ? start : end - 0.02;
      element.playbackRate = 1;
    } else {
      // Gently catch up on small drifts instead of jumping.
      element.playbackRate = lag > _maxLatency / 2 ? 1.1 : 1;
    }
    if (element.paused) {
      element.play().toDart.ignore();
    }
    if (++_ticks % 20 == 0) _prune();
  }

  void _prune({bool force = false}) {
    final buffer = _sourceBuffer;
    if (buffer == null || buffer.updating) return;
    final current = element.currentTime;
    final keep = force ? 0.5 : 4.0;
    if (current > keep + 1) {
      try {
        buffer.remove(0, current - keep);
      } catch (_) {
        // Removing is best-effort.
      }
    }
  }

  bool _isTypeSupported(String mime) {
    final ctor = globalContext.has('MediaSource')
        ? globalContext['MediaSource']
        : globalContext['ManagedMediaSource'];
    if (ctor == null) return false;
    return ((ctor as JSObject).callMethod<JSBoolean>(
      'isTypeSupported'.toJS,
      mime.toJS,
    )).toDart;
  }

  web.MediaSource _createMediaSource() {
    // Prefer the standard MediaSource; iPhone Safari only has
    // ManagedMediaSource, which extends it.
    if (globalContext.has('MediaSource')) return web.MediaSource();
    final ctor = globalContext['ManagedMediaSource'] as JSFunction;
    return ctor.callAsConstructor<web.MediaSource>();
  }

  void _teardownSource() {
    _updateEnd?.cancel();
    _updateEnd = null;
    _sourceBuffer = null;
    _mediaSource = null;
    _muxer = null;
    _queue.clear();
    final url = _objectUrl;
    if (url != null) {
      element.removeAttribute('src');
      element.load();
      web.URL.revokeObjectURL(url);
      _objectUrl = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _liveEdgeTimer?.cancel();
    _frameEvents?.cancel();
    _teardownSource();
    element.remove();
  }
}
