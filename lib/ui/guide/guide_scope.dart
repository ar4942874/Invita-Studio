import 'package:flutter/material.dart';

import '../occasion_theme.dart';
import 'guide_controller.dart';

/// Publishes the [GuideController] down the tree.
///
/// It is an `InheritedNotifier`, so a target that depends on it rebuilds when
/// the tour moves — that is how the glow follows the current step without any
/// target holding its own listener.
class GuideScope extends InheritedNotifier<GuideController> {
  const GuideScope({
    super.key,
    required GuideController super.notifier,
    required super.child,
  });

  static GuideController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GuideScope>()?.notifier;
}

/// Marks the control a step points at.
///
/// Two jobs: it reports its rectangle so the spotlight can cut a hole around it,
/// and it throws the occasion's light on itself while it is the current step.
/// Outside a [GuideScope] it is a transparent wrapper, so the same widget can be
/// used in tests and previews without a tour.
class GuideTarget extends StatefulWidget {
  const GuideTarget({
    super.key,
    required this.anchor,
    required this.child,
    this.radius = 9,
  });

  final String anchor;
  final Widget child;

  /// Corner radius of the glow, so a pill-shaped control is not boxed in.
  final double radius;

  @override
  State<GuideTarget> createState() => _GuideTargetState();
}

class _GuideTargetState extends State<GuideTarget> {
  final GlobalKey _boxKey = GlobalKey(debugLabel: 'guide target');
  GuideController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = GuideScope.maybeOf(context);
    if (!identical(controller, _controller)) {
      _controller = controller;
      controller?.registerAnchor(widget.anchor);
      _scheduleMeasure();
    }
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
  }

  void _measure() {
    final controller = _controller;
    final box = _boxKey.currentContext?.findRenderObject();
    if (controller == null || box is! RenderBox || !box.attached || !box.hasSize) {
      return;
    }
    controller.reportAnchor(
      widget.anchor,
      box.localToGlobal(Offset.zero) & box.size,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = GuideScope.maybeOf(context);
    final active =
        controller != null &&
        controller.isVisible &&
        controller.current?.anchor == widget.anchor;
    if (active) _scheduleMeasure();
    final occasion = occasionFor(context);
    return AnimatedContainer(
      key: ValueKey('guide.target.${widget.anchor}'),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        boxShadow: active
            ? [
                BoxShadow(
                  color: occasion.accent.withValues(alpha: .34),
                  blurRadius: 24,
                  spreadRadius: 6,
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: KeyedSubtree(key: _boxKey, child: widget.child),
    );
  }
}
