# Project notes — Invita Studio

## Toolchain

- Flutter SDK: `C:/flutter_3477/flutter/bin/flutter.bat` (Flutter 3.47.7 / Dart 3.13.5).
  Not on `PATH`; call it by absolute path.
- **`flutter test` fails with "Unable to connect to flutter_tester process:
  WebSocketException: Invalid WebSocket upgrade request"** when the shell's
  `http_proxy`/`https_proxy` are set — the local test socket is routed through the
  proxy. Always run:
  ```
  env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
      NO_PROXY=127.0.0.1,localhost \
      "/c/flutter_3477/flutter/bin/flutter.bat" test --no-pub --concurrency=1 test packages/flutter_canvas_editor/test
  ```
  `flutter analyze` and `flutter build web` are unaffected by the proxy.
- Python with numpy (needed by `tool/generate_music.py` and the art generators):
  `C:/Users/PMLS/AppData/Local/Programs/Python/Python311/python.exe`. The managed
  python 3.13 has no numpy.
- `dart format` from `C:/Program Files/dart-sdk` is Dart 3.2.2 — older than the
  project's formatter, so do not reformat files with it (it rewrites untouched code).

## Conventions

- Docs must not pin a test-*case* count (the catalogue scales it); cite the number of
  test files instead. `test/docs_consistency_test.dart` enforces this plus the
  catalogue counts (60 designs + 9 legacy = 69) and bans stale UI copy.
- Bundled tunes are immutable assets: their length comes from the generated
  `lib/domain/category_music_durations.g.dart`, never from the draft's stored value.
- One rule decides whether an export needs the music file:
  `exportNeedsAudio(audio, isWeb:)` in `lib/services/video/export_media.dart`.
