import 'dart:typed_data';

import '../multipart/multipart_demuxer.dart';
import 'access_unit.dart';
import 'annexb_splitter.dart';
import 'nal_unit.dart';
import 'sps.dart';

/// Turns HTTP response bytes into H.264 [AccessUnit]s.
///
/// Handles both `multipart/*` responses (each part carrying Annex-B data, as
/// served by many embedded cameras) and raw Annex-B streams. Part boundaries
/// do not need to align with NAL units or frames: part bodies are
/// concatenated before splitting.
///
/// This class is pure Dart and works on every platform, which makes it
/// useful for tests, recording or server-side tooling.
class H264StreamParser {
  /// Creates a parser for a response with the given [contentType]. When the
  /// content type is `multipart/*` with a boundary, multipart framing is
  /// removed; otherwise the bytes are treated as raw Annex-B.
  H264StreamParser({String? contentType, Duration Function()? clock})
    : _demuxer = switch (multipartBoundary(contentType)) {
        final boundary? => MultipartDemuxer(boundary),
        null => null,
      },
      _assembler = AccessUnitAssembler(clock: clock);

  final MultipartDemuxer? _demuxer;
  final AnnexBSplitter _splitter = AnnexBSplitter();
  final AccessUnitAssembler _assembler;

  NalUnit? _sps;
  NalUnit? _pps;
  SpsInfo? _spsInfo;

  /// Whether the response is being parsed as multipart.
  bool get isMultipart => _demuxer != null;

  /// The most recent sequence parameter set seen in the stream.
  NalUnit? get sps => _sps;

  /// The most recent picture parameter set seen in the stream.
  NalUnit? get pps => _pps;

  /// The parsed [sps], once one has been seen.
  SpsInfo? get spsInfo => _spsInfo;

  /// Feeds a chunk of the response body and returns completed access units.
  List<AccessUnit> add(Uint8List chunk) {
    final units = <AccessUnit>[];
    final demuxer = _demuxer;
    if (demuxer == null) {
      _feed(chunk, units);
    } else {
      for (final part in demuxer.add(chunk)) {
        _feed(part.body, units);
      }
    }
    return units;
  }

  /// Flushes buffered data at the end of the stream.
  List<AccessUnit> close() {
    final units = <AccessUnit>[];
    for (final nal in _splitter.flush()) {
      _onNal(nal, units);
    }
    final last = _assembler.flush();
    if (last != null) units.add(last);
    return units;
  }

  void _feed(Uint8List bytes, List<AccessUnit> out) {
    for (final nal in _splitter.add(bytes)) {
      _onNal(nal, out);
    }
  }

  void _onNal(NalUnit nal, List<AccessUnit> out) {
    if (nal.type == NalUnitType.sps) {
      try {
        _spsInfo = SpsInfo.parse(nal);
        _sps = nal;
      } on FormatException {
        // Ignore a corrupt SPS; keep the previous one.
      }
    } else if (nal.type == NalUnitType.pps) {
      _pps = nal;
    }
    final unit = _assembler.add(nal);
    if (unit != null) out.add(unit);
  }
}
