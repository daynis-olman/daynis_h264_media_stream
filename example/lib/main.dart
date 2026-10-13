import 'dart:async';

import 'package:daynis_h264_media_stream/daynis_h264_media_stream.dart';
import 'package:flutter/material.dart';

/// Plays a live H.264 stream and its JSON telemetry.
///
/// Start the bundled test server first (from the package root):
///
///   dart run tool/stream_server.dart --file path/to/video.mp4
void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'H.264 stream',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1FA8C2),
        useMaterial3: true,
      ),
      home: const StreamPage(),
    );
  }
}

class StreamPage extends StatefulWidget {
  const StreamPage({super.key});

  @override
  State<StreamPage> createState() => _StreamPageState();
}

class _StreamPageState extends State<StreamPage> {
  // Query parameters allow deep links such as
  // ?url=http://192.168.1.100/camera-setup/video-frame&backend=mediaSource&autoplay=1
  final _query = Uri.base.queryParameters;
  late final _url = TextEditingController(
    text: _query['url'] ?? 'http://localhost:8080/video-frame',
  );
  late H264Backend _backend =
      H264Backend.values.asNameMap()[_query['backend']] ?? H264Backend.auto;
  StreamSubscription<MultipartPart>? _telemetry;
  Map<String, Object?>? _pose;
  H264StreamController? _controller;

  @override
  void initState() {
    super.initState();
    if (_query['autoplay'] == '1') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _play());
    }
  }

  void _play() {
    _stop();
    final uri = Uri.parse(_url.text);
    final controller = H264StreamController(
      uri: uri,
      options: H264StreamOptions(backend: _backend),
    )..start();
    // Companion telemetry served next to the video, e.g. head pose.
    _telemetry = connectMultipart(uri.resolve('head-pose')).listen(
      (part) => setState(() => _pose = part.json as Map<String, Object?>?),
      onError: (Object _) => setState(() => _pose = null),
    );
    setState(() => _controller = controller);
  }

  void _stop() {
    _telemetry?.cancel();
    _telemetry = null;
    _controller?.dispose();
    setState(() {
      _controller = null;
      _pose = null;
    });
  }

  @override
  void dispose() {
    _telemetry?.cancel();
    _controller?.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      appBar: AppBar(title: const Text('daynis_h264_media_stream')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 360,
                  child: TextField(
                    controller: _url,
                    decoration: const InputDecoration(
                      labelText: 'Stream URL',
                      filled: true,
                    ),
                    onSubmitted: (_) => _play(),
                  ),
                ),
                SegmentedButton<H264Backend>(
                  segments: [
                    for (final b in H264Backend.values)
                      ButtonSegment(value: b, label: Text(b.name)),
                  ],
                  selected: {_backend},
                  onSelectionChanged: (s) =>
                      setState(() => _backend = s.single),
                ),
                FilledButton.icon(
                  onPressed: _play,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                ),
                OutlinedButton.icon(
                  onPressed: _stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              ],
            ),
          ),
          Expanded(
            child: controller == null
                ? const Center(
                    child: Text(
                      'Press Play',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      H264StreamView(
                        controller: controller,
                        placeholderBuilder: (context, c) => Center(
                          child: Text(
                            c.state == H264StreamState.error
                                ? 'Error: ${c.error}'
                                : '${c.state.name}…',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        top: 12,
                        child: _StatsBadge(controller: controller, pose: _pose),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatsBadge extends StatelessWidget {
  const _StatsBadge({required this.controller, this.pose});

  final H264StreamController controller;
  final Map<String, Object?>? pose;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final stats = controller.stats;
        final lines = [
          '${controller.state.name} · ${controller.backend?.name ?? '-'}',
          if (controller.videoInfo != null) '${controller.videoInfo}',
          '${stats.framesPerSecond.toStringAsFixed(0)} fps · ${stats.kilobitsPerSecond.toStringAsFixed(0)} kbps',
          'decoded ${stats.framesDecoded} · dropped ${stats.framesDropped} · reconnects ${stats.reconnects}',
          if (pose != null)
            'yaw ${pose!['head_yaw_deg']}° · pitch ${pose!['head_pitch_deg']}° · ${pose!['distance']} m',
        ];
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              lines.join('\n'),
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        );
      },
    );
  }
}
