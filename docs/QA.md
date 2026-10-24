# Verification record

**Date:** 16 October 2026  
**SDK:** Flutter 3.47.7 / Dart 3.13.5  
**Environment:** baseline browser checks on a Linux sandbox with real headless Chromium 156 via Playwright 1.64.1; the Flutter SDK runs (analyze/test/web build) on the project machine (Windows, PowerShell) with Flutter 3.47.7 / Dart 3.13.5.

> **Scope note.** The `Executed successfully` table below is the recorded
> image-editor baseline (the commit before the video increment); its 12 + 7
> browser checks were run against the compiled web build with headless
> Chromium 156 via Playwright 1.64.1. The video editor, MP4 exporter and both
> native encoders were added afterwards. The full Flutter suite — including the
> video model/exporter tests — now runs and passes on the project machine
> (Flutter 3.47.7 / Dart 3.13.5), `flutter analyze` is clean and
> `flutter build web` succeeds; see
> [the video verification report](VIDEO.md). What is still **not** executed is
> everything that needs a real device: no APK/IPA, no native encode, no share
> sheet. Treat native-only MP4 claims as source-only until then.
>
> **Suite size.** This record deliberately does not pin a number of test
> *cases*: the generated design tests scale with the catalogue, so a hand-typed
> total drifts silently. `test/docs_consistency_test.dart` checks the number of
> test *files* and the catalogue counts instead. For the number of cases, read
> the output of `flutter test`.

## Video increment (Dart suite runs; native pending)

| Check | Result |
|---|---|
| Dart syntax parse (tree-sitter-dart orchard grammar) over 71 repo files | 0 errors in new/modified video code; 1 pre-existing grammar ambiguity in `canvas_editor_controller.dart` |
| Reference render: 15 s, 1080 × 1920, 30 fps, artwork + 10 animated layers | Playable MP4; 450 decoded video frames; 15.00 s |
| Reference render with music | AAC-LC 44.1 kHz stereo; mean −23.2 dB, peak −13.6 dB |
| Reference render without music | No audio stream |
| Container | `isom`, `moov` before `mdat`, bt709 tags |
| Timeline / project / media tests (`test/video_*_test.dart`) | **Pass** on Flutter 3.47.7 / Dart 3.13.5 |
| Tune-length and export-preflight tests (`test/category_music_test.dart`, `test/export_preflight_test.dart`, `test/video_export_dialog_test.dart`) | **Pass** — WAV headers match the generated map; the export dialog resolves a bundled tune and blocks on a missing clip |
| `flutter analyze`, `flutter test`, `flutter build web --release` | **Pass** — analyzer clean, full suite green, web release builds |
| Android encoder, iOS encoder, share sheet, device playback | **Not executed** — no JDK/Android SDK/Xcode/device |

The sample MP4s are produced by `tool/reference_sample.py`, a development-only
renderer that reproduces the app's bundled artwork, fonts, layout constants and
`evaluateTimeline` timings. They are **not** app output. See
`docs/samples/README.md` for measured properties and regeneration commands.

## Executed successfully

| Check | Result |
|---|---|
| Dependency resolution with `pubspec.lock` | Passed |
| `flutter analyze` | **No issues found** |
| `flutter test --concurrency=1 test packages/flutter_canvas_editor/test` | **64 passed** (image-editor baseline) |
| Full suite (`flutter test test packages/flutter_canvas_editor/test`) | **All 21 test files pass** |
| `flutter build web --release --no-web-resources-cdn --no-wasm-dry-run -O1` | **Built successfully** |
| Real compiled-app browser workflow checks | **12 passed** |
| Real compiled-app photo-card browser checks | **7 passed** |
| Browser page errors / console errors / external-resource requests | **0 / 0 / 0** in the checked workflows |
| Downloaded PNG/JPEG decoded independently with Pillow | Correct signatures, formats and dimensions |
| iOS Info.plist syntax | Parsed successfully; this is not a native build test |
| Published upstream editor archive checksum | Matches pub.dev version metadata |

## Flutter test coverage

- Every design across all three formats (9 legacy + 60 category designs = 207 combinations): complete IDs, dimensions and editable project roundtrip.
- Each celebration offers exactly ten of its own designs; every bundled design ships art for each format plus a thumbnail and every category ships a bundled tune.
- Growing a field re-stacks the linked wording into a single column with no vertical overlap that stays inside the page.
- Creating a project from a category pre-selects that category's bundled tune, and its declared length is measured from the bundled WAV header (not a fixed guess), so trim handles match the real track.
- Export preflight: a bundled tune resolves through `loadBundledTune`, the music file is only required when it would actually be muxed (native, unmuted), and a missing clip or track is reported with a one-tap fix instead of throwing mid-render.
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
- Event settings: changing the celebration swaps the bundled tune, keeps imported music, applies a matching design without losing the typed words, and never reflows the same template twice.
- Duplicate draft: forks a new ID (document ID follows), keeps the copy title inside 80 characters, opens the copy, leaves the original intact and refuses a 13th draft.
- Structured event: `EventDateTime` encode/decode/validation, `.ics` structure and CRLF/octet folding (including Urdu text), Google Calendar links, RSVP URL validation and relative "edited 2 h ago" labels.
- Catalogue: the picker opens on the project category, "All designs" reaches sixty, starring moves a design into favourites, "Surprise me" always changes the card, and recently-used reflects the last applied design.
- Catalogue scale: only the visible rows are built, page two is absent from the tree until "Show more" is pressed, the remaining count is exact, and design thumbnails decode at tile width instead of source size. Previews decode at thumbnail size by default, keep their layout at any decode width, and every bundled background resolves back to its own design.
- The details panel shows the structured calendar line once a date is picked, and the event sheet applies a category change from the UI.
- Responsive widget layouts at **320, 390, 850, 1024 and 1440 pixels**, including mobile sheets/export setup.
- Actual canvas drag/inline-edit gestures and undo, not only controller method calls.
- Four retained upstream test files covering color, document JSON, hit testing, coordinates and history.

## Browser workflows

`tool/browser/smoke.cjs` runs against the actual compiled Flutter application over HTTP. It starts with isolated browser contexts and blocks requests outside the app origin.

Desktop (**1440 px**), all driven through the real semantics tree:

1. Boots on the guided start using locally served renderer, fonts and artwork.
2. Completes the wizard — category, names/venue, a catalogue design — and lands in the studio with those details.
3. Creates/downloads a genuine 2× Classic **PNG (2160 × 3024)** and checks the signature.
4. Catalogue: "All designs" reaches sixty, "For you" returns to ten, starring moves a design into Favourites, and "Surprise me" applies a *different* design (verified through the serialized draft, since autosave is debounced).
5. Switches to **Story** and confirms the reflow keeps the names.
6. **Event settings** changes the celebration to Birthday; the saved category follows.
7. **Invitation actions**: picking a date unlocks `Save .ics` / Google Calendar and the RSVP code section.
8. **Duplicate draft** adds a second draft and reports it.
9. Downloads editable JSON and checks the document content, category and format.
10. Reloads and restores the draft, its celebration and the relative edit time.
11. Imports the JSON into a fresh browser session and selects an imported layer.

Mobile: a **390 px** wizard + Details sheet edits the real document, and a **320 px** viewport downloads a genuine 2× Square **PNG (2160 × 2160)**.

Final assertions: zero uncaught page errors, zero console errors, zero external network requests in those workflows. Run log with timestamps and per-check status is written to `artifacts/browser/smoke-report.json`; screenshots of home, studio, favourites, event settings and the invitation actions sit beside it.

A separate actual browser download of the default Classic template was also decoded as **PNG, 2160 × 3024**. The independent checks are recorded in `docs/qa/download-validation.json`; the corresponding examples are in `examples/exports/`.

Note: `tool/browser/smoke.cjs` drives the *current* guided start, catalogue grid, event sheet and actions. Flutter merges sibling text into a parent node's `aria-label`, so the script asserts through a small helper that reads both `aria-label` and text content; design tiles expose one concise accessible name and exclude the card preview from semantics.

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
- Photo cropping/filters and the cloud/RSVP backend.
- Everything native about the video feature: Android/iOS compilation, MediaCodec/AVAssetWriter encode, background-clip extraction, music muxing, device playback, cancellation on device, share sheets and delivery. The code exists; the runs do not.
- Audible music in the **native** in-app preview (native builds bake music into the export only; the browser preview plays it while the browser export stays silent).

The first default build attempt ran parallel JavaScript/Wasm compilation and exceeded this 2 GB sandbox’s memory; it was stopped. The successfully built and browser-tested release uses JavaScript/O1 with the additional Wasm dry run disabled. Wasm output and O4 release performance were not validated.

## Required next native checks

1. Set up JDK 17/21 + Android SDK, run `flutter doctor`, debug-build and test on a physical Android device (minimum API 24).
2. On macOS configure signing, build for an iOS 15+ device and test an iPad share popover.
3. Export all formats at 1×/2× with bundled fonts; check saved dimensions and artwork after repeated exports, rotation, undo and background/foreground transitions.
4. Exercise cancellation, storage failures/quota, app-documents saving and actual receiving apps. Verify any system Photos action and its permission prompt.
5. Replace debug signing, choose final app IDs, review notices/privacy text and perform release-store checks before production distribution.
6. Video: import a clip and music, export Story/Square/Classic at both qualities on Android (API 24+) and iOS 15+, verify H.264/AAC/450-frame output with `ffprobe`/MediaInfo, cancel mid-export and confirm no partial file, kill the app mid-export, exercise missing-media relinking, and share the MP4 into at least two receiving apps.
