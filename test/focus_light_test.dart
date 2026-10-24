import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invitation_studio/domain/focus_light.dart';
import 'package:invitation_studio/domain/project.dart';
import 'package:invitation_studio/services/focus_light_export.dart';
import 'package:invitation_studio/ui/widgets/focus_light_layer.dart';

/// Renders [setting] over a flat paper colour and returns the raw pixels.
Future<ByteData> _render(FocusLightSetting setting, {int side = 120}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    Paint()..color = const Color(0xFFF7F1E6),
  );
  paintFocusLight(canvas, Size(side.toDouble(), side.toDouble()), setting);
  final picture = recorder.endRecording();
  final image = await picture.toImage(side, side);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return data!;
}

int _pixel(ByteData data, int x, int y, {int side = 120}) {
  final offset = (y * side + x) * 4;
  return data.getUint32(offset);
}

Future<Uint8List> _pngOf(Color colour, {int side = 96}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    Paint()..color = colour,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(side, side);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  group('a light is a setting, not a style', () {
    test('off is the default and writes nothing', () {
      const setting = FocusLightSetting.none;
      expect(setting.isOff, isTrue);
      expect(
        FocusLightSetting.decode(null),
        const FocusLightSetting(light: FocusLight.none),
      );
    });

    test('a chosen light survives a JSON round trip', () {
      const setting = FocusLightSetting(
        light: FocusLight.goldenHour,
        intensity: .4,
      );
      final restored = FocusLightSetting.decode(setting.toJson());
      expect(restored, setting);
      expect(restored.light, FocusLight.goldenHour);
      expect(restored.intensity, .4);
    });

    test('an unknown light opens as no light instead of throwing', () {
      expect(
        FocusLightSetting.decode({'light': 'disco', 'intensity': 2}).light,
        FocusLight.none,
      );
      expect(
        FocusLightSetting.decode({'light': 'warmGlow', 'intensity': 9})
            .intensity,
        1.0,
      );
      expect(
        FocusLightSetting.decode({'light': 'warmGlow', 'intensity': -3})
            .intensity,
        0.0,
      );
    });

    test('every offered light has words and a source', () {
      expect(FocusLight.choices, hasLength(4));
      for (final light in FocusLight.choices) {
        expect(light.label, isNotEmpty);
        expect(light.description, isNotEmpty);
        expect(light.spread, greaterThan(0));
      }
      expect(FocusLight.byName('candlelight'), FocusLight.candlelight);
      expect(FocusLight.byName('nope'), isNull);
    });
  });

  group('the project carries the light', () {
    test('a saved light comes back with the draft', () {
      final project = StudioProject.sample().copyWith(
        focusLight: const FocusLightSetting(
          light: FocusLight.coolDawn,
          intensity: .3,
        ),
      );
      final restored = StudioProject.decode(project.encode());
      expect(restored.focusLight.light, FocusLight.coolDawn);
      expect(restored.focusLight.intensity, .3);
    });

    test('a project written before lights opens with no light', () {
      final project = StudioProject.sample();
      final json = project.toJson()..remove('focusLight');
      final decoded = StudioProject.decode(jsonEncode(json));
      expect(decoded.focusLight.isOff, isTrue);
      expect(project.toJson().containsKey('focusLight'), isFalse);
    });
  });

  group('the light actually paints', () {
    test('a lit card differs from an unlit one', () async {
      final plain = await _render(FocusLightSetting.none);
      final lit = await _render(
        const FocusLightSetting(light: FocusLight.warmGlow),
      );
      expect(
        _pixel(plain, 60, 10),
        isNot(_pixel(lit, 60, 10)),
        reason: 'the pool of light must reach the top of the card',
      );
      expect(
        _pixel(plain, 4, 116),
        isNot(_pixel(lit, 4, 116)),
        reason: 'the falloff must darken the corners',
      );
    });

    test('zero strength is the same as off', () async {
      final off = await _render(FocusLightSetting.none);
      final zero = await _render(
        const FocusLightSetting(light: FocusLight.warmGlow, intensity: 0),
      );
      expect(_pixel(zero, 60, 10), _pixel(off, 60, 10));
    });

    test('a stronger light paints more', () async {
      final soft = await _render(
        const FocusLightSetting(light: FocusLight.warmGlow, intensity: .2),
      );
      final strong = await _render(
        const FocusLightSetting(light: FocusLight.warmGlow, intensity: .9),
      );
      expect(_pixel(strong, 60, 6), isNot(_pixel(soft, 60, 6)));
    });
  });

  group('the export path composites the same light', () {
    test('a PNG comes back lit, at the same size', () async {
      final source = await _pngOf(const Color(0xFF3366AA));
      final lit = await applyFocusLightToPng(
        source,
        const FocusLightSetting(light: FocusLight.warmGlow, intensity: .8),
      );
      expect(lit, isNot(equals(source)));
      // Still a PNG signature.
      expect(lit.sublist(0, 8), source.sublist(0, 8));

      Future<List<int>> pixelsOf(Uint8List png) async {
        final codec = await ui.instantiateImageCodec(png);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 96);
        expect(frame.image.height, 96);
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        frame.image.dispose();
        codec.dispose();
        return data!.buffer.asUint8List();
      }

      final before = await pixelsOf(source);
      final after = await pixelsOf(lit);
      // The pool of light sits near the top centre; a warm glow can only make
      // that pixel brighter and redder.
      final offset = (6 * 96 + 48) * 4;
      int brightness(List<int> rgba) =>
          rgba[offset] + rgba[offset + 1] + rgba[offset + 2];
      expect(brightness(after), greaterThan(brightness(before)));
      expect(after[offset], greaterThan(before[offset]));
    });

    test('an unlit card is returned untouched', () async {
      final source = await _pngOf(const Color(0xFF3366AA));
      final same = await applyFocusLightToPng(source, FocusLightSetting.none);
      expect(identical(same, source), isTrue);
    });
  });

  group('the layer is decoration, never a gesture target', () {
    testWidgets('an off layer paints nothing and stays out of the way', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 100,
            height: 140,
            child: FocusLightLayer(setting: FocusLightSetting.none),
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(FocusLightLayer),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });

    testWidgets('a lit layer ignores pointers over the canvas', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                GestureDetector(
                  onTap: () => tapped = true,
                  child: const SizedBox.expand(child: ColoredBox(color: Colors.white)),
                ),
                const Positioned.fill(
                  child: FocusLightLayer(
                    setting: FocusLightSetting(light: FocusLight.warmGlow),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tapAt(const Offset(200, 300));
      expect(tapped, isTrue);
    });
  });
}
