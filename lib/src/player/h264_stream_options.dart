/// Decoding strategy used to render the stream.
enum H264Backend {
  /// Pick automatically: [webCodecs] in secure contexts (HTTPS or
  /// localhost) where `VideoDecoder` exists, otherwise [mediaSource].
  auto,

  /// The WebCodecs `VideoDecoder`, drawing frames onto a canvas. Lowest
  /// latency; requires a secure context.
  webCodecs,

  /// Media Source Extensions (`MediaSource` or Safari's
  /// `ManagedMediaSource`) fed with fragmented MP4 muxed in Dart. Works on
  /// plain `http://` origins such as embedded devices.
  mediaSource,
}

/// Lifecycle of an [H264StreamController].
enum H264StreamState {
  /// Created but not started.
  idle,

  /// Opening the HTTP connection.
  connecting,

  /// Connected; waiting for parameter sets and a keyframe.
  waitingForKeyframe,

  /// Frames are being decoded and shown.
  playing,

  /// The connection dropped or stalled; a new attempt is scheduled.
  reconnecting,

  /// Paused because the page is hidden (see
  /// [H264StreamOptions.pauseWhenHidden]).
  paused,

  /// Stopped by [H264StreamController.stop].
  stopped,

  /// Failed and not retrying. See [H264StreamController.error].
  error,
}

/// Configuration for an [H264StreamController].
class H264StreamOptions {
  /// Creates stream options. All values have sensible defaults for a live
  /// camera feed.
  const H264StreamOptions({
    this.backend = H264Backend.auto,
    this.frameRate,
    this.maxLatency = const Duration(milliseconds: 300),
    this.autoReconnect = true,
    this.reconnectDelay = const Duration(milliseconds: 500),
    this.maxReconnectDelay = const Duration(seconds: 5),
    this.stallTimeout = const Duration(seconds: 4),
    this.pauseWhenHidden = true,
    this.headers = const {},
  });

  /// Which decoder to use. Defaults to [H264Backend.auto].
  final H264Backend backend;

  /// Nominal frame rate. When `null`, the rate signalled in the SPS is used,
  /// falling back to the measured arrival rate.
  final double? frameRate;

  /// Maximum allowed delay behind the newest received frame before playback
  /// jumps to the live edge (Media Source backend).
  final Duration maxLatency;

  /// Whether to reconnect automatically when the stream ends, errors or
  /// stalls.
  final bool autoReconnect;

  /// Initial delay before reconnecting; doubles after each failed attempt.
  final Duration reconnectDelay;

  /// Upper bound for the reconnect delay.
  final Duration maxReconnectDelay;

  /// A connection that delivers no bytes for this long is treated as
  /// stalled and reconnected.
  final Duration stallTimeout;

  /// Close the connection while the page is hidden and reconnect when it is
  /// visible again. Saves device bandwidth and avoids a backlog of stale
  /// frames.
  final bool pauseWhenHidden;

  /// Extra HTTP request headers, e.g. authorisation.
  final Map<String, String> headers;
}

/// Live statistics for an [H264StreamController], updated once per second.
class H264StreamStats {
  /// Creates a statistics snapshot.
  const H264StreamStats({
    this.framesReceived = 0,
    this.framesDecoded = 0,
    this.framesDropped = 0,
    this.bytesReceived = 0,
    this.framesPerSecond = 0,
    this.kilobitsPerSecond = 0,
    this.reconnects = 0,
  });

  /// Access units received since [H264StreamController.start].
  final int framesReceived;

  /// Access units handed to the decoder.
  final int framesDecoded;

  /// Access units dropped (waiting for a keyframe, or decoder backlog).
  final int framesDropped;

  /// Total body bytes received.
  final int bytesReceived;

  /// Frames received during the last second.
  final double framesPerSecond;

  /// Bitrate over the last second.
  final double kilobitsPerSecond;

  /// Number of reconnections.
  final int reconnects;

  @override
  String toString() =>
      'H264StreamStats(${framesPerSecond.toStringAsFixed(1)} fps, '
      '${kilobitsPerSecond.toStringAsFixed(0)} kbps, decoded $framesDecoded, '
      'dropped $framesDropped, reconnects $reconnects)';
}
