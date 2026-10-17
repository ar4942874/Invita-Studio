# Verification record

**Date:** 16 October 2026  
**SDK:** Flutter 3.47.7 / Dart 3.13.5  
**Environment:** Linux sandbox; real headless Chromium 156 via Playwright 1.64.1 for web checks.

## Executed successfully

| Check | Result |
|---|---|
| Dependency resolution with `pubspec.lock` | Passed |
| `flutter analyze` | **No issues found** |
| `flutter test --concurrency=1 test packages/flutter_canvas_editor/test` | **64 passed** |
| `flutter build web --release --no-web-resources-cdn --no-wasm-dry-run -O1` | **Built successfully** |
| Real compiled-app browser workflow checks | **12 passed** |
| Real compiled-app photo-card browser checks | **7 passed** |
| Browser page errors / console errors / external-resource requests | **0 / 0 / 0** in the checked workflows |
| Downloaded PNG/JPEG decoded independently with Pillow | Correct signatures, formats and dimensions |
| iOS Info.plist syntax | Parsed successfully; this is not a native build test |
| Published upstream editor archive checksum | Matches pub.dev version metadata |

## Flutter test coverage

- All nine combinations of template and format: complete IDs, dimensions and editable project roundtrip.
- Photo layers: downscale/encode preparation, add/select/fit/delete, persistence and rejection of remote references, filesystem paths, sub-background ordering and unknown fit modes.
- Text fitting without ellipsis or loss of wording; basic first-strong direction cases.
- Rejection of filesystem/remote image references, unknown node/font types, duplicate IDs, oversized canvases/fonts/input and missing linked fields.
- Rapid sequential form changes without lost values; form/canvas/undo synchronization.
- Undoable template/format changes, custom-layer retention and linked-layer deletion protection.
- Coalesced font-size slider history, persisted local drafts and restoration of recent drafts.
- Clipping warnings and default-layout bounds.
- PNG signatures and 2× dimensions; identical selected/unselected export bytes; repeated exports without invalidating cached assets.
- Real JPEG signature/dimensions and transparent-to-white alpha flattening.
- Immutable export snapshot while an image load is deliberately delayed and the live document changes.
- Explicit export failure for missing artwork and rejection of unsafe scales/allocations.
- Correct single-line center alignment in rendered pixels.
- Responsive widget layouts at **320, 390, 850, 1024 and 1440 pixels**, including mobile sheets/export setup.
- Actual canvas drag/inline-edit gestures and undo, not only controller method calls.
- Four retained upstream test files covering color, document JSON, hit testing, coordinates and history (14 upstream tests).

## Browser workflows

`tool/browser/smoke.cjs` runs against the actual compiled Flutter application over HTTP. It starts with isolated browser contexts and blocks requests outside the app origin.

1. Boots using locally served renderer, fonts and artwork.
2. Changes names/venue through real form input and observes the serialized local draft.
3. Switches to After dark and Story while retaining text.
4. Creates/downloads a genuine **2160 × 3840 JPEG**.
5. Exercises unsupported browser sharing and checks that the UI directs the user to download instead of claiming success.
6. Downloads editable JSON and checks actual document content.
7. Reloads and restores the saved invitation.
8. Imports the JSON into a fresh browser session.
9. Selects an imported text layer for styling.
10. Edits through a **390 px** mobile Details sheet.
11. Switches to Rosewater/Square and downloads a genuine **2160 × 2160 PNG** from a **320 px** viewport.
12. Asserts no uncaught errors or external network dependencies in those workflows.

A separate actual browser download of the default Classic template was also decoded as **PNG, 2160 × 3024**. The independent checks are recorded in `docs/qa/download-validation.json`; the corresponding examples are in `examples/exports/`.

## Photo-card browser workflow

`tool/browser/photo.cjs` drives the same compiled build: it feeds a generated PNG through the real file picker and asserts the resulting behavior end to end.

1. Imports a local photo as an embedded JPEG data-URL image layer above the background, with a real frame.
2. Shows the photo inspector for the selected layer.
3. Changes box-fit to **Contain** and observes the serialized change.
4. Exports a PNG that renders the photo.
5. Exports editable project JSON that embeds the photo layer.
6. Reloads and restores the saved photo.
7. Asserts no uncaught errors or external network dependencies in those workflows.

## Evidence

- `docs/qa/flutter_analyze.log`
- `docs/qa/flutter_tests.log`
- `docs/qa/web_build.log`
- `docs/qa/browser-smoke-report.json`
- `docs/qa/photo-report.json`
- `docs/qa/download-validation.json`
- `docs/screenshots/desktop.png`, `mobile.png`, `export.png`
- Editable sample: `examples/projects/after-dark-story.invita.json`

The browser’s `force` click option bypasses DOM overlap checks on Flutter’s semantic overlay; physical click coordinates still enter Flutter’s hit-testing pipeline. Form typing waits for the actual text-editing input. Menu items use accessible roles because Flutter exposes their labels through ARIA. Flutter widget tests separately exercise real canvas gestures. These are not static HTML/mock-controller browser checks.

## Not validated / not delivered

- **No Android APK/AAB or iOS IPA.** No Android SDK or Xcode/device environment was available. Android/iOS compilation, native plugin execution and signing remain untested.
- Native share-sheet actions, Save to Photos/Files, iPad presentation, receiving apps, delivery/caption support and cancellation behavior on physical devices.
- Safari/Firefox, every browser Web Share permission policy, low-memory phones, real mobile software-keyboard behavior or every font/language combination.
- Full accessibility, collision detection, long-session performance, storage durability/security or print-prepress certification.
- Photo cropping/filters, cloud/RSVP backend, animation or MP4.

The first default build attempt ran parallel JavaScript/Wasm compilation and exceeded this 2 GB sandbox’s memory; it was stopped. The successfully built and browser-tested release uses JavaScript/O1 with the additional Wasm dry run disabled. Wasm output and O4 release performance were not validated.

## Required next native checks

1. Set up JDK 17/21 + Android SDK, run `flutter doctor`, debug-build and test on a physical Android device (minimum API 24).
2. On macOS configure signing, build for an iOS 15+ device and test an iPad share popover.
3. Export all formats at 1×/2× with bundled fonts; check saved dimensions and artwork after repeated exports, rotation, undo and background/foreground transitions.
4. Exercise cancellation, storage failures/quota, app-documents saving and actual receiving apps. Verify any system Photos action and its permission prompt.
5. Replace debug signing, choose final app IDs, review notices/privacy text and perform release-store checks before production distribution.
