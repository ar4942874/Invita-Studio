import 'package:flutter/material.dart';

import '../../domain/focus_light.dart';

/// Paints the card's focus light over whatever sits beneath it.
///
/// Sized by its parent, so the same widget works for the artboard, a 34 px
/// thumbnail and the export dialog's large preview. It never takes a gesture:
/// the light is decoration, and the canvas editor underneath must keep every
/// drag and tap.
class FocusLightLayer extends StatelessWidget {
  const FocusLightLayer({super.key, required this.setting});

  final FocusLightSetting setting;

  @override
  Widget build(BuildContext context) {
    if (setting.isOff) return const SizedBox.shrink();
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(painter: _FocusLightPainter(setting)),
      ),
    );
  }
}

class _FocusLightPainter extends CustomPainter {
  const _FocusLightPainter(this.setting);

  final FocusLightSetting setting;

  @override
  void paint(Canvas canvas, Size size) => paintFocusLight(canvas, size, setting);

  @override
  bool shouldRepaint(covariant _FocusLightPainter old) =>
      old.setting != setting;
}
