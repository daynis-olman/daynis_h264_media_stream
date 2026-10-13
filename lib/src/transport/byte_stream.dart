import 'dart:typed_data';

export 'byte_stream_stub.dart'
    if (dart.library.js_interop) 'byte_stream_web.dart'
    if (dart.library.io) 'byte_stream_io.dart';

/// An open streaming HTTP response.
abstract interface class ByteStreamConnection {
  /// The HTTP status code.
  int get statusCode;

  /// The response `Content-Type` header, if any.
  String? get contentType;

  /// Response body chunks as they arrive. Completes when the server closes
  /// the response or [close] is called.
  Stream<Uint8List> get bytes;

  /// Aborts the request. Safe to call more than once.
  void close();
}

/// Thrown when a stream cannot be opened or fails while running.
class H264StreamException implements Exception {
  /// Creates an exception with a human-readable [message].
  const H264StreamException(this.message, {this.statusCode, this.cause});

  /// What went wrong.
  final String message;

  /// The HTTP status code, when the server answered with an error.
  final int? statusCode;

  /// The underlying error, if any.
  final Object? cause;

  @override
  String toString() =>
      'H264StreamException: $message'
      '${statusCode != null ? ' (HTTP $statusCode)' : ''}'
      '${cause != null ? ': $cause' : ''}';
}
