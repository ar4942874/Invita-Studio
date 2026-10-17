import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The validated SDK, quoted in the README, the QA record, the video report and
/// the CI workflow. Keep these in one place so the docs cannot drift apart.
const _sdkVersion = '3.47.7';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: 'expected $path to exist');
  return file.readAsStringSync();
}

/// Reads a `StudioColors` token's rendered hex (e.g. `canvas` -> `#FAF8F4`) so
/// the web shell can be checked against the single source of truth.
String _themeHex(String token) {
  final source = _read('lib/ui/studio_theme.dart');
  final match = RegExp(
    'static const $token = Color\\(0xFF([0-9A-Fa-f]{6})\\)',
  ).firstMatch(source);
  expect(match, isNotNull, reason: 'StudioColors.$token hex not found');
  return '#${match!.group(1)!.toUpperCase()}';
}

void main() {
  group('docs stay consistent with the code', () {
    test('the validated Flutter SDK version is stated consistently', () {
      const paths = [
        'README.md',
        'docs/QA.md',
        'docs/VIDEO.md',
        '.github/workflows/ci.yml',
      ];
      for (final path in paths) {
        expect(_read(path), contains(_sdkVersion), reason: path);
      }
    });

    test('no stale, trust-breaking claims remain in the docs', () {
      const forbidden = [
        'image-first',
        '27 combinations',
        'not executed here',
        'MP4 export runs only on Android/iOS',
        'Web and desktop can preview and edit timing but cannot encode',
      ];
      const docs = [
        'README.md',
        'docs/QA.md',
        'docs/VIDEO.md',
        'docs/ARCHITECTURE.md',
      ];
      for (final path in docs) {
        final lower = _read(path).toLowerCase();
        for (final phrase in forbidden) {
          expect(
            lower,
            isNot(contains(phrase.toLowerCase())),
            reason: '$path still says "$phrase"',
          );
        }
      }
    });

    test('package metadata no longer calls this an image editor', () {
      final pubspec = _read('pubspec.yaml');
      expect(pubspec.toLowerCase(), isNot(contains('image-first')));
      final description = pubspec
          .split('\n')
          .firstWhere((line) => line.startsWith('description:'));
      expect(description.toLowerCase(), isNot(contains('image editor')));
    });

    test('the web shell paints the studio theme palette', () {
      final html = _read('web/index.html');
      final manifest = _read('web/manifest.json');
      expect(html, contains(_themeHex('canvas')), reason: 'index.html background');
      expect(
        manifest,
        contains(_themeHex('canvas')),
        reason: 'manifest background_color',
      );
      expect(
        manifest,
        contains(_themeHex('ink')),
        reason: 'manifest theme_color',
      );
      // The pre-reskin green palette must be gone.
      for (final stale in ['#425B4A', '#F5F6F1', '#858A82']) {
        expect(html.toUpperCase(), isNot(contains(stale)), reason: stale);
        expect(manifest.toUpperCase(), isNot(contains(stale)), reason: stale);
      }
    });

    test('the changelog records the browser video export', () {
      expect(_read('CHANGELOG.md').toLowerCase(), contains('mediarecorder'));
    });

    test('the front page describes the suite without a drifting count', () {
      // The executed count scales with the design catalogue (one generated test
      // per design × format), so the README must not pin a bare number.
      final count = RegExp(r'(?<![=\w.])\d+\s+tests?\b');
      expect(
        count.hasMatch(_read('README.md')),
        isFalse,
        reason: 'README should not pin a fixed test count; see docs/QA.md',
      );
    });

    test('the verification records agree on the suite size, and it is real', () {
      int countFiles(String dir) => Directory(dir)
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('_test.dart'))
          .length;
      final actual =
          countFiles('test') + countFiles('packages/flutter_canvas_editor/test');
      final stated = RegExp(r'(\d+)\s+test files\b');
      String? sizeOf(String path) => stated.firstMatch(_read(path))?.group(1);
      final qa = sizeOf('docs/QA.md');
      final video = sizeOf('docs/VIDEO.md');
      expect(qa, isNotNull, reason: 'QA.md should state the suite size');
      expect(video, isNotNull, reason: 'VIDEO.md should state the suite size');
      expect(qa, video, reason: 'QA.md and VIDEO.md disagree on the suite size');
      expect(
        int.parse(qa!),
        actual,
        reason: 'the cited suite size should match the files on disk',
      );
    });
  });
}
