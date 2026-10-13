import 'byte_stream.dart';

/// Opens a streaming GET request. Unsupported on this platform.
Future<ByteStreamConnection> openByteStream(
  Uri uri, {
  Map<String, String> headers = const {},
}) =>
    throw UnsupportedError('HTTP streaming is not supported on this platform');
