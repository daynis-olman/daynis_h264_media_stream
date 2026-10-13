import 'dart:convert';
import 'dart:typed_data';

/// One body part of a `multipart/*` HTTP response.
class MultipartPart {
  /// Creates a part from its [headers] (lower-cased names) and [body].
  const MultipartPart(this.headers, this.body);

  /// Part headers with lower-cased names, e.g. `content-type`.
  final Map<String, String> headers;

  /// The raw part body.
  final Uint8List body;

  /// The part's `Content-Type` header, if present.
  String? get contentType => headers['content-type'];

  /// The body decoded as UTF-8 text.
  String get text => utf8.decode(body, allowMalformed: true);

  /// The body decoded as JSON.
  Object? get json => jsonDecode(text);

  @override
  String toString() =>
      'MultipartPart(${contentType ?? 'no content-type'}, ${body.length} bytes)';
}

/// Extracts the `boundary` parameter from a `multipart/*` content type, e.g.
/// `multipart/x-mixed-replace; boundary=frame` → `frame`.
///
/// Returns `null` if [contentType] is not multipart or has no boundary.
String? multipartBoundary(String? contentType) {
  if (contentType == null) return null;
  final lower = contentType.toLowerCase();
  if (!lower.trimLeft().startsWith('multipart/')) return null;
  for (final param in contentType.split(';').skip(1)) {
    final eq = param.indexOf('=');
    if (eq < 0) continue;
    if (param.substring(0, eq).trim().toLowerCase() != 'boundary') continue;
    var value = param.substring(eq + 1).trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    return value.isEmpty ? null : value;
  }
  return null;
}

/// Incrementally parses a `multipart/x-mixed-replace` (or any `multipart/*`)
/// byte stream into [MultipartPart]s.
///
/// Tolerates CRLF or bare LF line endings, a missing leading CRLF before the
/// first boundary, and boundaries written with or without the leading `--`.
/// A `Content-Length` part header is used when present; otherwise a part ends
/// at the next boundary line.
class MultipartDemuxer {
  /// Creates a demuxer for parts separated by [boundary].
  MultipartDemuxer(String boundary)
    : _delimiter = ascii.encode(
        boundary.startsWith('--') ? boundary : '--$boundary',
      );

  final Uint8List _delimiter;
  Uint8List _buffer = Uint8List(0);
  int _length = 0;
  int _pos = 0;
  _State _state = _State.preamble;
  Map<String, String> _headers = const {};
  int? _contentLength;

  /// Whether the closing boundary (`--boundary--`) has been seen.
  bool get isClosed => _state == _State.closed;

  /// Appends [chunk] and returns every part completed by it.
  List<MultipartPart> add(Uint8List chunk) {
    _append(chunk);
    final parts = <MultipartPart>[];
    var progressed = true;
    while (progressed && _state != _State.closed) {
      progressed = switch (_state) {
        _State.preamble => _readDelimiter(),
        _State.headers => _readHeaders(),
        _State.body => _readBody(parts),
        _State.closed => false,
      };
    }
    _compact();
    return parts;
  }

  bool _readDelimiter() {
    final at = _indexOf(_delimiter, _pos);
    if (at < 0) {
      // Keep enough bytes to match a delimiter split across chunks.
      _pos = (_length - _delimiter.length).clamp(_pos, _length);
      return false;
    }
    final after = at + _delimiter.length;
    if (after + 2 > _length) return false;
    if (_buffer[after] == 0x2d && _buffer[after + 1] == 0x2d) {
      _state = _State.closed;
      return false;
    }
    final lineEnd = _indexOfLineEnd(after);
    if (lineEnd == null) return false;
    _pos = lineEnd.$2;
    _state = _State.headers;
    return true;
  }

  bool _readHeaders() {
    final headers = <String, String>{};
    var cursor = _pos;
    while (true) {
      final lineEnd = _indexOfLineEnd(cursor);
      if (lineEnd == null) return false;
      final line = latin1.decode(
        Uint8List.sublistView(_buffer, cursor, lineEnd.$1),
      );
      cursor = lineEnd.$2;
      if (line.isEmpty) break;
      final colon = line.indexOf(':');
      if (colon > 0) {
        headers[line.substring(0, colon).trim().toLowerCase()] = line
            .substring(colon + 1)
            .trim();
      }
    }
    _headers = headers;
    _contentLength = int.tryParse(headers['content-length'] ?? '');
    _pos = cursor;
    _state = _State.body;
    return true;
  }

  bool _readBody(List<MultipartPart> out) {
    final length = _contentLength;
    if (length != null) {
      if (_pos + length > _length) return false;
      out.add(
        MultipartPart(
          _headers,
          Uint8List.fromList(
            Uint8List.sublistView(_buffer, _pos, _pos + length),
          ),
        ),
      );
      _pos += length;
      _state = _State.preamble;
      return true;
    }
    // A boundary inside a body must start a line; binary payloads can contain
    // the delimiter bytes elsewhere.
    var at = _indexOf(_delimiter, _pos);
    while (at > _pos && _buffer[at - 1] != 0x0a) {
      at = _indexOf(_delimiter, at + 1);
    }
    if (at < 0) return false;
    // The line break before the delimiter belongs to the boundary.
    var end = at;
    if (end > _pos && _buffer[end - 1] == 0x0a) end--;
    if (end > _pos && _buffer[end - 1] == 0x0d) end--;
    out.add(
      MultipartPart(
        _headers,
        Uint8List.fromList(Uint8List.sublistView(_buffer, _pos, end)),
      ),
    );
    _pos = at;
    _state = _State.preamble;
    return true;
  }

  /// Returns (start of line break, index after line break) for the first
  /// line break at or after [from].
  (int, int)? _indexOfLineEnd(int from) {
    for (var i = from; i < _length; i++) {
      if (_buffer[i] == 0x0a) {
        final start = i > from && _buffer[i - 1] == 0x0d ? i - 1 : i;
        return (start, i + 1);
      }
    }
    return null;
  }

  int _indexOf(Uint8List needle, int from) {
    final first = needle[0];
    final last = _length - needle.length;
    outer:
    for (var i = from; i <= last; i++) {
      if (_buffer[i] != first) continue;
      for (var j = 1; j < needle.length; j++) {
        if (_buffer[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  void _append(Uint8List chunk) {
    final needed = _length + chunk.length;
    if (needed > _buffer.length) {
      final grown = Uint8List(needed < 8192 ? 8192 : needed * 2);
      grown.setRange(0, _length, _buffer);
      _buffer = grown;
    }
    _buffer.setRange(_length, needed, chunk);
    _length = needed;
  }

  void _compact() {
    if (_pos == 0) return;
    _buffer.setRange(0, _length - _pos, _buffer, _pos);
    _length -= _pos;
    _pos = 0;
  }
}

enum _State { preamble, headers, body, closed }
