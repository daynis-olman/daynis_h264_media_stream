import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../h264/access_unit.dart';
import '../h264/nal_unit.dart';
import '../h264/sps.dart';
import '../player/h264_stream_options.dart';
import '../transport/byte_stream.dart';
import 'video_renderer.dart';

/// Decodes with the WebCodecs `VideoDecoder` and paints onto a `<canvas>`.
class WebCodecsRenderer implements VideoRenderer {
  /// Creates the renderer and its canvas.
  WebCodecsRenderer({
    required void Function(Object error) onError,
    required void Function() onFrame,
  }) : _onError = onError,
       _onFrame = onFrame {
    final style = element.style;
    style.width = '100%';
    style.height = '100%';
    style.objectFit = 'contain';
    style.display = 'block';
  }

  /// The canvas frames are drawn onto.
  final web.HTMLCanvasElement element = web.HTMLCanvasElement();
  final void Function(Object error) _onError;
  final void Function() _onFrame;

  /// Frames waiting in the decoder before delta frames are dropped. High
  /// enough to absorb the burst replayed after configuration; only a decoder
  /// that is persistently slower than real time hits it.
  static const int maxDecodeQueue = 30;

  web.VideoDecoder? _decoder;
  web.CanvasRenderingContext2D? _context;
  NalUnit? _sps;
  NalUnit? _pps;
  bool _needKeyframe = true;

  @override
  H264Backend get backend => H264Backend.webCodecs;

  @override
  Future<void> configure(SpsInfo info, NalUnit sps, NalUnit pps) async {
    _closeDecoder();
    final config = web.VideoDecoderConfig(
      codec: info.codecString,
      optimizeForLatency: true,
    );
    final support = await web.VideoDecoder.isConfigSupported(config).toDart;
    if (!(support.supported)) {
      throw H264StreamException('WebCodecs cannot decode ${info.codecString}');
    }
    element.width = info.width;
    element.height = info.height;
    _context = element.getContext('2d') as web.CanvasRenderingContext2D?;
    final decoder = web.VideoDecoder(
      web.VideoDecoderInit(
        output: _paint.toJS,
        error: ((web.DOMException e) => _onError(
          H264StreamException('Decoder error', cause: e.message),
        )).toJS,
      ),
    );
    decoder.configure(config);
    _decoder = decoder;
    _sps = sps;
    _pps = pps;
    _needKeyframe = true;
  }

  @override
  bool decode(AccessUnit unit, Duration duration) {
    final decoder = _decoder;
    if (decoder == null || decoder.state != 'configured') return false;
    final key = unit.isKeyframe;
    if (!key && (_needKeyframe || decoder.decodeQueueSize > maxDecodeQueue)) {
      _needKeyframe = true;
      return false;
    }
    // Annex-B decoding without an avcC description needs in-band parameter
    // sets on every keyframe.
    final data = key && unit.firstOfType(NalUnitType.sps) == null
        ? unit.toAnnexB(prepend: [_sps!, _pps!])
        : unit.toAnnexB();
    decoder.decode(
      web.EncodedVideoChunk(
        web.EncodedVideoChunkInit(
          type: key ? 'key' : 'delta',
          timestamp: unit.receivedAt.inMicroseconds,
          duration: duration.inMicroseconds,
          data: data.toJS,
        ),
      ),
    );
    _needKeyframe = false;
    return true;
  }

  void _paint(web.VideoFrame frame) {
    final context = _context;
    if (context != null) {
      context.drawImage(frame, 0, 0, element.width, element.height);
      _onFrame();
    }
    frame.close();
  }

  @override
  void requireKeyframe() => _needKeyframe = true;

  void _closeDecoder() {
    final decoder = _decoder;
    if (decoder != null && decoder.state != 'closed') decoder.close();
    _decoder = null;
  }

  @override
  void dispose() {
    _closeDecoder();
    element.remove();
  }
}
