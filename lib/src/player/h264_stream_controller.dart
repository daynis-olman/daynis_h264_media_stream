import 'dart:async';

import 'package:flutter/foundation.dart';

import '../h264/access_unit.dart';
import '../h264/h264_stream_parser.dart';
import '../h264/sps.dart';
import '../platform/platform_surface.dart';
import '../platform/video_renderer.dart';
import '../transport/byte_stream.dart';
import 'h264_stream_options.dart';

/// Connects to a live H.264 HTTP stream and decodes it for an
/// [H264StreamView].
///
/// The stream may be `multipart/x-mixed-replace` (each part carrying Annex-B
/// NAL units, the format produced by many embedded cameras and by JMuxer
/// style servers) or a raw Annex-B byte stream.
///
/// ```dart
/// final controller = H264StreamController(
///   uri: Uri.parse('http://192.168.1.100/camera-setup/video-frame'),
/// )..start();
///
/// // In build():
/// H264StreamView(controller: controller);
///
/// // When done:
/// controller.dispose();
/// ```
///
/// One controller owns one HTTP connection. Show it in any number of places
/// over time (for example a page, then a dialog) without reconnecting; only
/// one [H264StreamView] can display it at a time.
class H264StreamController extends ChangeNotifier {
  /// Creates a controller for the stream at [uri]. Call [start] to connect.
  H264StreamController({
    required this.uri,
    this.options = const H264StreamOptions(),
  }) : _surface = createPlatformSurface() {
    if (options.pauseWhenHidden) {
      _visibility = _surface.visibilityChanges.listen(_onVisibilityChanged);
    }
  }

  /// The stream endpoint.
  final Uri uri;

  /// Stream configuration.
  final H264StreamOptions options;

  final PlatformSurface _surface;
  StreamSubscription<bool>? _visibility;

  H264StreamState _state = H264StreamState.idle;
  Object? _error;
  SpsInfo? _videoInfo;
  H264Backend? _backend;
  H264StreamStats _stats = const H264StreamStats();

  /// Current lifecycle state.
  H264StreamState get state => _state;

  /// The last error, when [state] is [H264StreamState.error] or
  /// [H264StreamState.reconnecting].
  Object? get error => _error;

  /// Video format from the stream's SPS, once known.
  SpsInfo? get videoInfo => _videoInfo;

  /// The decoder in use, once configured.
  H264Backend? get backend => _backend;

  /// Statistics, refreshed every second while running.
  H264StreamStats get stats => _stats;

  /// Whether this platform can play H.264 streams.
  bool get isSupported => _surface.isSupported;

  /// Whether the controller is trying to stream (between [start] and
  /// [stop]).
  bool get isActive => _wantRunning;

  /// The platform element hosting the video, embedded by [H264StreamView].
  /// An implementation detail; apps should not need it.
  Object? get hostElement => _surface.hostElement;

  bool _wantRunning = false;
  bool _disposed = false;
  int _generation = 0;
  ByteStreamConnection? _connection;
  StreamSubscription<Uint8List>? _bytes;
  H264StreamParser? _parser;
  VideoRenderer? _renderer;
  Future<void>? _configuring;
  String? _configuredFor;
  final List<AccessUnit> _pendingSinceKeyframe = [];
  Timer? _reconnectTimer;
  Timer? _watchdog;
  Timer? _statsTimer;
  Duration _nextDelay = Duration.zero;
  DateTime _lastBytesAt = DateTime.now();
  bool _hadFirstFrame = false;

  int _framesReceived = 0,
      _framesDecoded = 0,
      _framesDropped = 0,
      _bytesReceived = 0,
      _reconnects = 0;
  int _windowFrames = 0, _windowBytes = 0;
  Duration? _lastArrival;
  double? _measuredInterval;

  /// Connects and starts decoding. Does nothing if already active.
  Future<void> start() async {
    _checkNotDisposed();
    if (_wantRunning) return;
    if (!_surface.isSupported) {
      _setState(
        H264StreamState.error,
        error: UnsupportedError(
          'H.264 streaming needs a browser with WebCodecs or Media Source Extensions',
        ),
      );
      return;
    }
    _wantRunning = true;
    _nextDelay = options.reconnectDelay;
    _statsTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => _publishStats(),
    );
    await _connect();
  }

  /// Disconnects and stops decoding. The last frame stays on screen.
  Future<void> stop() async {
    _wantRunning = false;
    _reconnectTimer?.cancel();
    _statsTimer?.cancel();
    _statsTimer = null;
    _closeConnection();
    if (!_disposed) _setState(H264StreamState.stopped);
  }

  /// Stops and reconnects immediately.
  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> _connect({bool isRetry = false}) async {
    final generation = ++_generation;
    _setState(
      isRetry ? H264StreamState.reconnecting : H264StreamState.connecting,
      error: isRetry ? _error : null,
    );
    try {
      final connection = await openByteStream(uri, headers: options.headers);
      if (generation != _generation || !_wantRunning) {
        connection.close();
        return;
      }
      if (connection.statusCode < 200 || connection.statusCode > 299) {
        connection.close();
        throw H264StreamException(
          'Unexpected response from $uri',
          statusCode: connection.statusCode,
        );
      }
      _connection = connection;
      _parser = H264StreamParser(contentType: connection.contentType);
      _renderer?.requireKeyframe();
      _pendingSinceKeyframe.clear();
      _hadFirstFrame = false;
      _lastBytesAt = DateTime.now();
      _setState(H264StreamState.waitingForKeyframe);
      _bytes = connection.bytes.listen(
        _onBytes,
        onError: (Object e) => _onFailure(e, generation),
        onDone: () =>
            _onFailure(const H264StreamException('Stream ended'), generation),
        cancelOnError: true,
      );
      _watchdog?.cancel();
      _watchdog = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (DateTime.now().difference(_lastBytesAt) > options.stallTimeout) {
          _onFailure(const H264StreamException('Stream stalled'), generation);
        }
      });
    } catch (e) {
      _onFailure(e, generation);
    }
  }

  void _onBytes(Uint8List chunk) {
    _lastBytesAt = DateTime.now();
    _bytesReceived += chunk.length;
    _windowBytes += chunk.length;
    final parser = _parser;
    if (parser == null) return;
    for (final unit in parser.add(chunk)) {
      _onAccessUnit(unit, parser);
    }
  }

  void _onAccessUnit(AccessUnit unit, H264StreamParser parser) {
    _framesReceived++;
    _windowFrames++;
    _trackArrival(unit.receivedAt);

    final sps = parser.sps, pps = parser.pps, info = parser.spsInfo;
    if (sps == null || pps == null || info == null) {
      _framesDropped++;
      return;
    }
    final signature =
        '${info.codecString}/${info.width}x${info.height}/${pps.bytes.length}';
    if (_configuredFor != signature) {
      // Hold frames from the latest keyframe so the first picture appears as
      // soon as the decoder is ready.
      if (unit.isKeyframe) _pendingSinceKeyframe.clear();
      if (unit.isKeyframe || _pendingSinceKeyframe.isNotEmpty) {
        _pendingSinceKeyframe.add(unit);
      }
      _configuring ??= _configure(info, parser, signature);
      return;
    }
    if (_configuring != null) {
      _pendingSinceKeyframe.add(unit);
      return;
    }
    _decode(unit);
  }

  Future<void> _configure(
    SpsInfo info,
    H264StreamParser parser,
    String signature,
  ) async {
    final generation = _generation;
    try {
      var backend = _surface.resolveBackend(options.backend);
      if (backend == null) {
        throw UnsupportedError(
          'No decoder available for ${options.backend.name}',
        );
      }
      try {
        await _installRenderer(backend, info, parser);
      } on Object {
        // WebCodecs may reject a profile that MSE can still play.
        if (options.backend != H264Backend.auto ||
            backend != H264Backend.webCodecs) {
          rethrow;
        }
        backend = H264Backend.mediaSource;
        await _installRenderer(backend, info, parser);
      }
      if (generation != _generation) return;
      _configuredFor = signature;
      _videoInfo = info;
      _backend = backend;
      _configuring = null;
      final pending = List.of(_pendingSinceKeyframe);
      _pendingSinceKeyframe.clear();
      pending.forEach(_decode);
      notifyListeners();
    } catch (e) {
      _configuring = null;
      _wantRunning = false;
      _closeConnection();
      _setState(H264StreamState.error, error: e);
    }
  }

  Future<void> _installRenderer(
    H264Backend backend,
    SpsInfo info,
    H264StreamParser parser,
  ) async {
    _renderer?.dispose();
    final renderer = _renderer = _surface.createRenderer(
      backend,
      maxLatency: options.maxLatency,
      onError: _onRendererError,
      onFrame: _onFrameShown,
    );
    await renderer.configure(info, parser.sps!, parser.pps!);
  }

  void _decode(AccessUnit unit) {
    final renderer = _renderer;
    if (renderer == null) return;
    if (renderer.decode(unit, _frameDuration())) {
      _framesDecoded++;
    } else {
      _framesDropped++;
    }
  }

  void _onFrameShown() {
    if (_hadFirstFrame) return;
    _hadFirstFrame = true;
    _nextDelay = options.reconnectDelay;
    _setState(H264StreamState.playing);
  }

  void _onRendererError(Object error) {
    final generation = _generation;
    _configuredFor = null; // Reconfigure on the next keyframe.
    _renderer?.dispose();
    _renderer = null;
    _onFailure(error, generation);
  }

  void _onFailure(Object error, int generation) {
    if (generation != _generation || _disposed) return;
    _closeConnection();
    if (!_wantRunning) return;
    if (!options.autoReconnect) {
      _wantRunning = false;
      _setState(H264StreamState.error, error: error);
      return;
    }
    _error = error;
    _reconnects++;
    _setState(H264StreamState.reconnecting, error: error);
    final delay = _nextDelay;
    final doubled = _nextDelay * 2;
    _nextDelay = doubled > options.maxReconnectDelay
        ? options.maxReconnectDelay
        : doubled;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (_wantRunning && !_disposed) _connect(isRetry: true);
    });
  }

  void _onVisibilityChanged(bool visible) {
    if (!_wantRunning) return;
    if (!visible) {
      _generation++;
      _reconnectTimer?.cancel();
      _closeConnection();
      _setState(H264StreamState.paused);
    } else if (_state == H264StreamState.paused) {
      _connect();
    }
  }

  void _closeConnection() {
    _watchdog?.cancel();
    _watchdog = null;
    _bytes?.cancel();
    _bytes = null;
    _connection?.close();
    _connection = null;
    _parser = null;
    _lastArrival = null;
  }

  void _trackArrival(Duration at) {
    final last = _lastArrival;
    _lastArrival = at;
    if (last == null) return;
    final interval = (at - last).inMicroseconds.toDouble();
    if (interval <= 0 || interval > 1e6) return;
    final measured = _measuredInterval;
    _measuredInterval = measured == null
        ? interval
        : measured * 0.9 + interval * 0.1;
  }

  Duration _frameDuration() {
    final fps = options.frameRate ?? _videoInfo?.frameRate;
    if (fps != null && fps > 0 && fps <= 240) {
      return Duration(
        microseconds: (Duration.microsecondsPerSecond / fps).round(),
      );
    }
    final measured = _measuredInterval;
    if (measured != null) {
      return Duration(microseconds: measured.round().clamp(4000, 200000));
    }
    return const Duration(microseconds: 33333);
  }

  void _publishStats() {
    _stats = H264StreamStats(
      framesReceived: _framesReceived,
      framesDecoded: _framesDecoded,
      framesDropped: _framesDropped,
      bytesReceived: _bytesReceived,
      framesPerSecond: _windowFrames.toDouble(),
      kilobitsPerSecond: _windowBytes * 8 / 1000,
      reconnects: _reconnects,
    );
    _windowFrames = 0;
    _windowBytes = 0;
    notifyListeners();
  }

  void _setState(H264StreamState state, {Object? error}) {
    if (_disposed) return;
    _state = state;
    _error = error;
    notifyListeners();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('H264StreamController was used after being disposed');
    }
  }

  @override
  void dispose() {
    _wantRunning = false;
    _generation++;
    _reconnectTimer?.cancel();
    _statsTimer?.cancel();
    _visibility?.cancel();
    _closeConnection();
    _renderer?.dispose();
    _renderer = null;
    _surface.dispose();
    _disposed = true;
    super.dispose();
  }
}
