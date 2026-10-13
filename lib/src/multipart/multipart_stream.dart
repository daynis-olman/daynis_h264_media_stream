import 'dart:async';

import '../transport/byte_stream.dart';
import 'multipart_demuxer.dart';

/// Connects to a `multipart/*` streaming endpoint and emits each part.
///
/// Useful for companion telemetry streams such as JSON metadata pushed
/// alongside a video feed:
///
/// ```dart
/// final sub = connectMultipart(Uri.parse('/camera/head-pose'))
///     .map((part) => part.json)
///     .listen(print);
/// // Later: sub.cancel() aborts the HTTP request.
/// ```
///
/// The request is made when the stream is listened to and aborted when the
/// subscription is cancelled. Errors are reported as [H264StreamException]s.
Stream<MultipartPart> connectMultipart(
  Uri uri, {
  Map<String, String> headers = const {},
}) {
  ByteStreamConnection? connection;
  StreamSubscription<void>? subscription;
  late final StreamController<MultipartPart> controller;
  controller = StreamController<MultipartPart>(
    onListen: () async {
      try {
        final conn = connection = await openByteStream(uri, headers: headers);
        if (conn.statusCode < 200 || conn.statusCode > 299) {
          throw H264StreamException(
            'Unexpected response from $uri',
            statusCode: conn.statusCode,
          );
        }
        final boundary = multipartBoundary(conn.contentType);
        if (boundary == null) {
          throw H264StreamException(
            'Expected a multipart response from $uri, got ${conn.contentType}',
          );
        }
        final demuxer = MultipartDemuxer(boundary);
        subscription = conn.bytes.listen(
          (chunk) {
            for (final part in demuxer.add(chunk)) {
              controller.add(part);
            }
          },
          onError: controller.addError,
          onDone: controller.close,
        );
      } catch (e, s) {
        connection?.close();
        if (!controller.isClosed) {
          controller.addError(e, s);
          await controller.close();
        }
      }
    },
    onCancel: () async {
      connection?.close();
      await subscription?.cancel();
    },
  );
  return controller.stream;
}
