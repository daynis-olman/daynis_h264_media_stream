import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'byte_stream.dart';

/// Opens a streaming GET request with `dart:io`.
Future<ByteStreamConnection> openByteStream(
  Uri uri, {
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    final response = await request.close();
    return _IoConnection(client, response);
  } catch (e) {
    client.close(force: true);
    throw H264StreamException('Could not connect to $uri', cause: e);
  }
}

class _IoConnection implements ByteStreamConnection {
  _IoConnection(this._client, this._response);

  final HttpClient _client;
  final HttpClientResponse _response;

  @override
  int get statusCode => _response.statusCode;

  @override
  String? get contentType =>
      _response.headers.value(HttpHeaders.contentTypeHeader);

  @override
  Stream<Uint8List> get bytes => _response.map(
    (chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
  );

  @override
  void close() => _client.close(force: true);
}
