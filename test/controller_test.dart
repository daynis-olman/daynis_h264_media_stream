import 'package:daynis_h264_media_stream/daynis_h264_media_stream.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports an error on platforms without browser decoders', () async {
    final controller = H264StreamController(
      uri: Uri.parse('http://localhost/video'),
    );
    addTearDown(controller.dispose);
    expect(controller.state, H264StreamState.idle);
    expect(controller.isSupported, isFalse);
    await controller.start();
    expect(controller.state, H264StreamState.error);
    expect(controller.error, isA<UnsupportedError>());
  });

  testWidgets('view shows the error builder when unsupported', (tester) async {
    final controller = H264StreamController(
      uri: Uri.parse('http://localhost/video'),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: H264StreamView(
          controller: controller,
          placeholderBuilder: (_, _) => const Text('connecting'),
          errorBuilder: (_, c) => Text('error: ${c.state.name}'),
        ),
      ),
    );
    expect(find.text('connecting'), findsOneWidget);
    await controller.start();
    await tester.pump();
    expect(find.text('error: error'), findsOneWidget);
  });

  test('options have live-friendly defaults', () {
    const options = H264StreamOptions();
    expect(options.backend, H264Backend.auto);
    expect(options.autoReconnect, isTrue);
    expect(options.maxLatency, const Duration(milliseconds: 300));
  });
}
