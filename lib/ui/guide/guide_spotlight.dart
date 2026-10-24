import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../occasion_theme.dart';
import '../studio_theme.dart';
import 'guide_controller.dart';
import 'guide_stop.dart';

/// Dims everything but the current control, then explains it.
///
/// The dim is four rectangles rather than one painted cut-out: each one is a
/// tap target that closes the tour, and the hole between them stays live, so
/// the person can use the control the tour is pointing at instead of just
/// reading about it.
class GuideSpotlight extends StatelessWidget {
  const GuideSpotlight({super.key, required this.controller});

  final GuideController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (!controller.isVisible) return const SizedBox.shrink();
      final stop = controller.current;
      if (stop == null) return const SizedBox.shrink();
      final occasion = occasionFor(context);
      return LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          var hole = controller.rectFor(stop.anchor);
          if (hole != null) {
            final clamped = hole
                .inflate(6)
                .intersect(Offset.zero & size);
            hole = clamped.width <= 0 || clamped.height <= 0 ? null : clamped;
          }
          return Stack(
            children: [
              ..._dim(context, size, hole, occasion),
              Positioned(
                left: 16,
                right: 16,
                top: _cardBelow(size, hole) ? null : 16,
                bottom: _cardBelow(size, hole) ? 16 : null,
                child: Align(
                  alignment: _cardBelow(size, hole)
                      ? Alignment.bottomCenter
                      : Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 384,
                      maxHeight: math.max(120, size.height - 32),
                    ),
                    // A very short screen scrolls the card rather than
                    // overflowing it; the copy is never clipped.
                    child: SingleChildScrollView(
                      child: _GuideCard(
                        controller: controller,
                        stop: stop,
                        occasion: occasion,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );

  /// True when the card should sit at the bottom of the screen: whenever the
  /// highlighted control is in the upper half, so the card never covers what it
  /// is describing. Pinning to the larger half (instead of estimating the
  /// card's height next to the hole) cannot overflow on a short screen.
  bool _cardBelow(Size size, Rect? hole) {
    if (hole == null) return true;
    return hole.center.dy < size.height / 2;
  }

  List<Widget> _dim(
    BuildContext context,
    Size size,
    Rect? hole,
    OccasionTheme occasion,
  ) {
    final colour = occasion.ink.withValues(alpha: .34);
    Widget shade(Rect rect) => Positioned(
      left: rect.left,
      top: rect.top,
      width: math.max(0, rect.width),
      height: math.max(0, rect.height),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: controller.dismiss,
        child: ColoredBox(color: colour),
      ),
    );
    if (hole == null) {
      return [shade(Offset.zero & size)];
    }
    return [
      shade(Rect.fromLTRB(0, 0, size.width, hole.top)),
      shade(Rect.fromLTRB(0, hole.bottom, size.width, size.height)),
      shade(Rect.fromLTRB(0, hole.top, hole.left, hole.bottom)),
      shade(Rect.fromLTRB(hole.right, hole.top, size.width, hole.bottom)),
    ];
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({
    required this.controller,
    required this.stop,
    required this.occasion,
  });

  final GuideController controller;
  final GuideStop stop;
  final OccasionTheme occasion;

  static IconData _icon(String name) => switch (name) {
    'details' => Icons.tune,
    'light' => Icons.light_mode_outlined,
    'text' => Icons.text_fields,
    'layers' => Icons.layers_outlined,
    'grid' => Icons.grid_view_outlined,
    'crop' => Icons.crop_portrait_outlined,
    'motion' => Icons.play_circle_outline,
    'export' => Icons.file_download_outlined,
    'send' => Icons.send_outlined,
    _ => Icons.auto_awesome_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final last = controller.position == controller.total;
    return Semantics(
      container: true,
      liveRegion: true,
      label:
          'Guided setup, step ${controller.position} of ${controller.total}: '
          '${stop.title}',
      child: GestureDetector(
        // A tap on the card's own blank space is not "tap away to dismiss".
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
        decoration: BoxDecoration(
          color: occasion.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: occasion.border),
          boxShadow: occasion.raisedShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(_icon(stop.icon), size: 14, color: occasion.accent),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    'GUIDED SETUP',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: StudioType.body,
                      fontSize: 9.5,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w600,
                      color: occasion.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${controller.position} of ${controller.total}',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: occasion.muted,
                  ),
                ),
                IconButton(
                  tooltip: 'Close the guided setup',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  onPressed: controller.dismiss,
                  icon: Icon(Icons.close, size: 16, color: occasion.muted),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                stop.title,
                style: TextStyle(
                  fontFamily: StudioType.display,
                  fontSize: 21,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.2,
                  color: occasion.ink,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                stop.body,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: occasion.inkSoft,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: occasion.wash,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 13,
                    color: occasion.meta,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      stop.why,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: occasion.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: controller.skip,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: Text(
                        'Not now',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: occasion.muted),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: controller.finishStep,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: Text(
                    last ? 'Finish' : 'Next',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}
