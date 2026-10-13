import 'package:flutter/widgets.dart';

import 'h264_stream_controller.dart';
import 'h264_stream_options.dart';
import 'platform_view.dart';

/// Builds a widget for a given [H264StreamController] state.
typedef H264StreamWidgetBuilder =
    Widget Function(BuildContext context, H264StreamController controller);

/// Displays the video of an [H264StreamController].
///
/// The video is letterboxed to fit the available space (CSS
/// `object-fit: contain`). Flutter widgets can be layered on top with a
/// `Stack`; the video ignores pointer events, so gestures reach Flutter.
///
/// ```dart
/// Stack(children: [
///   H264StreamView(
///     controller: controller,
///     placeholderBuilder: (context, c) => const Center(child: Text('Connecting…')),
///   ),
///   const Positioned(top: 12, left: 12, child: LiveBadge()),
/// ]);
/// ```
class H264StreamView extends StatelessWidget {
  /// Creates a view for [controller].
  const H264StreamView({
    super.key,
    required this.controller,
    this.placeholderBuilder,
    this.errorBuilder,
  });

  /// The stream to display.
  final H264StreamController controller;

  /// Shown on top of the video until the first frame is decoded, and while
  /// reconnecting or paused. Defaults to nothing (transparent).
  final H264StreamWidgetBuilder? placeholderBuilder;

  /// Shown when the controller is in [H264StreamState.error]. Defaults to
  /// [placeholderBuilder].
  final H264StreamWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (controller.isSupported) buildPlatformVideoView(controller),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final state = controller.state;
            if (state == H264StreamState.playing) {
              return const SizedBox.shrink();
            }
            final builder = state == H264StreamState.error
                ? (errorBuilder ?? placeholderBuilder)
                : placeholderBuilder;
            return builder?.call(context, controller) ??
                const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}
