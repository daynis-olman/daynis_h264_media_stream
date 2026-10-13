import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'h264_stream_controller.dart';

/// Builds the platform view hosting the video: a `<div>` into which the
/// controller's long-lived host element is moved.
Widget buildPlatformVideoView(H264StreamController controller) {
  return HtmlElementView.fromTagName(
    key: ObjectKey(controller),
    tagName: 'div',
    onElementCreated: (Object element) {
      final container = element as web.HTMLElement;
      container.style
        ..width = '100%'
        ..height = '100%'
        ..pointerEvents = 'none';
      final host = controller.hostElement;
      // The web surface always creates an HTMLDivElement.
      if (host != null) container.append(host as web.HTMLDivElement);
    },
  );
}
