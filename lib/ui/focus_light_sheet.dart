import 'package:flutter/material.dart';

import '../application/studio_controller.dart';
import '../domain/focus_light.dart';
import 'occasion_theme.dart';
import 'widgets/focus_light_layer.dart';

/// The Lights sheet: four lights, an off switch and one strength slider.
///
/// Every change is a real edit — it repaints the artboard, the thumbnails, the
/// video frames and the exported file through `paintFocusLight`.
class FocusLightSheet extends StatelessWidget {
  const FocusLightSheet({super.key, required this.studio});

  final StudioController studio;

  static Future<void> show(BuildContext context, StudioController studio) {
    // The sheet is pushed above the editor's scope, so capture the celebration
    // here and hand it down explicitly; otherwise a birthday card would open a
    // sage-green sheet from the fallback palette.
    final occasion = occasionFor(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: occasion.surface,
      builder: (sheetContext) => OccasionScope(
        theme: occasion,
        child: FocusLightSheet(studio: studio),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final occasion = occasionFor(context);
    return ListenableBuilder(
      listenable: studio,
      builder: (context, _) {
        final setting = studio.focusLight;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            0,
            22,
            18 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Focus lights',
                style: TextStyle(
                  fontFamily: 'CormorantGaramond',
                  fontSize: 27,
                  height: 1.1,
                  color: occasion.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'A pool of light and a soft falloff. It is part of the card, so '
                'it travels into the image, the PDF and the video.',
                style: TextStyle(fontSize: 12.5, color: occasion.muted),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _LightOption(
                    setting: FocusLightSetting(
                      light: FocusLight.none,
                      intensity: setting.intensity,
                    ),
                    selected: setting.light == FocusLight.none,
                    onTap: () => studio.updateFocusLight(
                      setting.copyWith(light: FocusLight.none),
                    ),
                  ),
                  for (final light in FocusLight.choices)
                    _LightOption(
                      setting: FocusLightSetting(
                        light: light,
                        intensity: setting.light == light
                            ? setting.intensity
                            : FocusLightSetting.defaultIntensity,
                      ),
                      selected: setting.light == light,
                      onTap: () => studio.updateFocusLight(
                        setting.copyWith(
                          light: light,
                          intensity: setting.light == FocusLight.none
                              ? FocusLightSetting.defaultIntensity
                              : setting.intensity,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    'Strength',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: occasion.ink,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(setting.intensity * 100).round()}%',
                    style: TextStyle(fontSize: 11.5, color: occasion.muted),
                  ),
                ],
              ),
              Slider(
                value: setting.intensity,
                // Off means off: moving the slider with no light chosen is a
                // no-op rather than a silently enabled glow.
                onChanged: setting.isOff && setting.light == FocusLight.none
                    ? null
                    : (value) {
                        studio.beginFocusSession();
                        studio.updateFocusLight(
                          setting.copyWith(intensity: value),
                        );
                      },
                onChangeStart: (_) => studio.beginFocusSession(),
                onChangeEnd: (_) => studio.endFocusSession(),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Undo and redo cover every change here.',
                      style: TextStyle(fontSize: 11, color: occasion.muted),
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LightOption extends StatelessWidget {
  const _LightOption({
    required this.setting,
    required this.selected,
    required this.onTap,
  });

  final FocusLightSetting setting;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final occasion = occasionFor(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${setting.light.label} light',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 96,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: selected ? occasion.accentSoft : occasion.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? occasion.accent : occasion.borderSoft,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  height: 58,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Color(0xFFF7F1E6)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            _SwatchRule(width: 44),
                            SizedBox(height: 5),
                            _SwatchRule(width: 30),
                          ],
                        ),
                      ),
                      FocusLightLayer(setting: setting),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                setting.light.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? occasion.accent : occasion.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two rules of "type" so each swatch shows what the light does to words.
class _SwatchRule extends StatelessWidget {
  const _SwatchRule({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: 3,
    decoration: BoxDecoration(
      color: const Color(0xFF3E2A1F).withValues(alpha: .55),
      borderRadius: BorderRadius.circular(2),
    ),
  );
}
