import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'byte_stream.dart';

/// Opens a streaming GET request with `fetch` and a `ReadableStream` reader.
Future<ByteStreamConnection> openByteStream(
  Uri uri, {
  Map<String, String> headers = const {},
}) async {
  final abort = web.AbortController();
  final requestHeaders = web.Headers();
  headers.forEach((name, value) => requestHeaders.append(name, value));
  final web.Response response;
  try {
    response = await web.window
        .fetch(
          uri.toString().toJS,
          web.RequestInit(
            method: 'GET',
            headers: requestHeaders,
            cache: 'no-store',
            signal: abort.signal,
          ),
        )
        .toDart;
  } catch (e) {
    throw H264StreamException('Could not connect to $uri', cause: e);
  }
  return _WebConnection(response, abort);
}

class _WebConnection implements ByteStreamConnection {
  _WebConnection(this._response, this._abort);

  final web.Response _response;
  final web.AbortController _abort;
  bool _closed = false;

  @override
  int get statusCode => _response.status;

  @override
  String? get contentType => _response.headers.get('content-type');

  @override
  late final Stream<Uint8List> bytes = _read();

  Stream<Uint8List> _read() async* {
    final body = _response.body;
    if (body == null) return;
    final reader = body.getReader() as web.ReadableStreamDefaultReader;
    try {
      while (!_closed) {
        final result = await reader.read().toDart;
        if (result.done) break;
        final value = result.value;
        if (value != null) yield (value as JSUint8Array).toDart;
      }
    } catch (e) {
      if (!_closed) throw H264StreamException('Stream interrupted', cause: e);
    } finally {
      reader.releaseLock();
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _abort.abort();
  }
}
