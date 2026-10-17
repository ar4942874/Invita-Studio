# Video invitations: implementation and verification

This document describes the animated-invitation increment: the model, the
rendering/export pipeline, the native encoder contracts, what was executed in
the build environment, and what still requires real devices.

## What is implemented

| Area | Implementation |
|---|---|
| Shared content | Image and video modes edit **one** `StudioController` / `DesignDocument`. Wording, fonts, colours and layer positions are the same objects; switching modes never copies or re-flows the document. |
| Timeline model | `lib/domain/video/timeline.dart`: versioned `VideoTimeline` with duration (5–30 s), fixed 30 fps, background clip settings, per-layer `LayerMotion` (visible window, entrance, exit), and one optional music track. |
| Animation | `fade`, `slideUp/Down/Left/Right`, `zoomIn/zoomOut` with duration 100–3000 ms, delay, and four easings. `evaluateTimeline` is the single evaluator used by both preview and export. |
| Preview | Play/pause, scrubbing, timecode, ruler, layer tracks, playhead and an inspector for window/effect/duration/easing. Frame painting goes through `TimelineFrameRenderer`. |
| Export | `VideoExporter` freezes the document + timeline, renders each frame offscreen, and streams raw RGBA to a native encoder through `VideoEncoderBackend`. Frames are never queued in memory. |
| Native encoders | Android `MediaCodec`/`MediaMuxer` (H.264 + AAC) and iOS `AVAssetWriter` (H.264, audio muxed in a second pass). Both are registered in `MainActivity.kt` / `AppDelegate.swift`. |
| Media storage | Imported clips and music live in managed app storage; project JSON stores asset IDs and trims only. Missing media is detected and explained instead of crashing. |
| Persistence | Project schema v2 adds `video`; v1 files migrate to default video settings. Strict validation rejects unknown effects, fps, out-of-range windows and unsafe asset IDs. |

## Data model

```text
StudioProject (schemaVersion 2)
├── document : DesignDocument          ← unchanged image-editor document
└── video    : VideoTimeline
    ├── enabled, durationMs, fps (30)
    ├── background { kind, assetId?, trimStartMs, trimEndMs, fit, loop }
    ├── motions[layerId] { visibleStartMs, visibleEndMs, entrance, exit }
    └── audio? { assetId, title, startMs, trimStartMs, trimEndMs,
                 durationMs, volume, fadeInMs, fadeOutMs }
```

* Layer IDs are the document's existing node IDs (`header`, `first`, `amp`, …,
  `extra.*`). There is no second field model and no duplicated text.
* `StudioProject.effectiveVideo` drops motions for deleted layers and clamps
  windows into the current duration. Controller, preview, inspector and exporter
  all read that validated view.
* `volume == 0` means **muted**, and the exporter writes an MP4 with **no audio
  track** rather than a silent AAC track. The export dialog states which case
  applies before the export starts.

### Determinism and bounded memory

* Timestamps are `frame * 1_000_000 ~/ fps`; playback time and wall-clock are
  never read by the exporter.
* One frame is in flight at a time (`await session.addFrame(...)` before the
  next render), so peak memory is one full-resolution RGBA buffer plus at most
  two decoded background frames (the export LRU has `maxEntries: 2`).
* The export snapshot copies the node list and motion map before the first
  `await`; edits made during an export cannot affect the file or the progress
  numbers.
* Cancellation is checked between frames and again after `toByteData`; on
  failure or cancel, the partial MP4 is deleted and every `ui.Image` handle is
  disposed in `finally`.

## Rendering path

`TimelineFrameRenderer.paintFrame`:

1. background colour and bundled artwork (the document's `BackgroundNode`);
2. the imported proxy frame, fitted with the same cover/contain/fill maths as a
   photo layer;
3. animated text/photo layers, transformed via `evaluateTimeline` (offset,
   scale) and painted with `CanvasPainter(nodeOpacities: …)`.

The preview widget and the exporter call the **same** method, so WYSIWYG is
structural rather than a promise. Text layout, Arabic shaping and fallback,
fonts and image fitting all come from the vendored engine.

The one engine change is opt-in: `CanvasPainter` accepts `nodeOpacities` and
calls `saveLayer` only when a layer is below 0.998 opacity. The static editor
passes no map and renders exactly as before.

## Native channel contracts

### `invita/video_media`

| Method | Arguments | Result |
|---|---|---|
| `probeVideo` | `{path}` | `{durationMs, width, height, hasAudio}` |
| `probeAudio` | `{path}` | duration in ms (int) |
| `extractFrames` | `{sourcePath, outputDir, fps, maxFrames, maxWidth, maxHeight, framePattern}` | `{count, width, height}` plus `extractionProgress {done,total}` callbacks |
| `cancelExtraction` | — | cancels the running extraction |

Extraction writes a bounded JPEG proxy (q82, ≤ 900 frames, ≤ 1080 × 1920,
even dimensions). Android uses `MediaMetadataRetriever`; iOS uses
`AVAssetImageGenerator` with zero tolerance. Importing is native-only; on web
and desktop the sheet says so and artwork still works.

### `invita/video_export`

| Method | Arguments |
|---|---|
| `open` | `{outputPath, width, height, fps, frameCount, bitrate, audio?}` → `sessionId` |
| `addFrame` | `{sessionId, timestampUs, bytes}` (RGBA8888, `width*height*4`) |
| `finish` | `{sessionId}` → final path |
| `cancel` | `{sessionId}` |

* **Android** (`VideoExportPlugin.kt`): prefers an H.264 encoder advertising
  Baseline, requires even dimensions, converts RGBA → I420/NV12, decodes the
  music with `MediaExtractor`/`MediaCodec`, applies trim, gain and linear fades,
  encodes AAC-LC 128 kb/s and muxes both tracks with `MediaMuxer`
  (`MUXER_OUTPUT_MPEG_4`). Video samples are buffered until the muxer has its
  output format, then written in PTS order.
* **iOS** (`VideoExportPlugin.swift`): `AVAssetWriter` with
  `AVVideoProfileLevelH264BaselineAutoLevel`, `AVVideoAllowFrameReorderingKey:
  false`, one key frame per second; RGBA → BGRA into pool-backed
  `CVPixelBuffer`s. When music is present a second pass builds an
  `AVMutableComposition`; straight trimming uses a passthrough export and only
  volume/fade changes force a re-encode with an `AVMutableAudioMix`.

Neither backend is compiled in this environment; see the verification section.

## Managed media and relinking

```text
<app documents>/InvitaStudioMedia/<projectId>/clips/<assetId>/
    manifest.json  f00000.jpg  f00001.jpg  …
<app documents>/InvitaStudioMedia/<projectId>/audio/<assetId>.<ext>
<app documents>/InvitaStudioExports/<slug>-<timestamp>.mp4
```

* Project JSON holds asset IDs, trims and music metadata — never base64 media.
* A deleted/copied media directory does not break the draft: the clip becomes
  "missing", the preview keeps rendering the artwork, and the settings sheet
  offers re-import or a switch back to artwork. Export refuses with an explicit
  message instead of writing a blank background.
* **Portable projects do not bundle media.** Exporting the editable JSON is a
  layout/word backup; moving a video project to another device requires moving
  `InvitaStudioMedia/<projectId>/` as well. This is stated in the settings sheet
  and in the README.
* Imported music is copied into app storage, so deleting the source file from
  the gallery/downloads folder does not remove the track.

## Export behaviour

* Quality options: **Story 1080 × 1920 @ 8 Mb/s** (the proven target) or
  **540 × 960 @ 3 Mb/s**. Output height is derived from the document aspect
  ratio, so Classic 5:7 and Square 1:1 also export (1080 × 1512 and
  1080 × 1080), matching the "preserve formats where the backend supports it"
  requirement.
* Progress reports stage + `frame/total`, never a fake percentage tied to
  playback.
* Failures surface the stage that failed (missing image, missing clip, encoder
  error, write error) and keep the configured draft intact.
* The result card shows dimensions, duration, frame count, byte size, audio
  track presence and the final path. Sharing uses
  `SharePlus.instance.share` with `mimeType: 'video/mp4'` and an iPad
  presentation anchor. The dialog explicitly says delivery is **not** confirmed
  by a share sheet.

## Platform matrix

| Platform | Preview + timeline editing | Background-clip import | MP4 export |
|---|---|---|---|
| Android 7+ (minSdk 24) | yes | yes (native) | yes (native encoder) |
| iOS 15+ | yes | yes (native) | yes (native encoder) |
| Web | yes (artwork, animations, scrubbing) | no — message shown | no — dialog explains the encoder is unavailable |
| Desktop | yes (artwork, animations, scrubbing) | no | no |

Web/desktop never pretend to export: `isVideoExportSupported` gates the action
and the dialog explains that preview and timing still work.

## Verification

### Executed in this environment

| Check | Result |
|---|---|
| Dart syntax parse of all 71 repo `.dart` files with the `tree-sitter-dart` (orchard) grammar | 1 pre-existing ambiguity in a vendored controller file (ternary/function-type parse), 0 errors in the new or modified files |
| Reference render of a 15 s / 1080 × 1920 / 30 fps invitation (artwork + 10 animated layers) | Playable MP4; ffmpeg decodes **450 video frames**, duration **15.00 s** |
| Silent and music variants | Silent variant has no audio stream; music variant has AAC-LC 44.1 kHz stereo, mean volume −23.2 dB, peak −13.6 dB |
| Container flags | `ftyp isom`, `moov` before `mdat` (fast start), bt709 colour tags |
| Project JSON round-trip / v1 migration / validation tests | Written (`test/video_project_test.dart`) — **not executed** |
| Timeline evaluation, easing, frame-index tests | Written (`test/video_timeline_test.dart`) — **not executed** |
| Media/manifest/frame-mapping/progress tests | Written (`test/video_media_test.dart`) — **not executed** |

### Not executed (blockers)

* `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build` — no
  Flutter/Dart SDK is obtainable in this sandbox (pub.dev, storage.googleapis.com
  and dart.dev are unreachable; the Dart binary bundled inside the
  `sass-embedded-linux-x64` npm package is an AOT runtime and cannot compile or
  analyse Dart code).
* Android build / emulator / device — no JDK, Android SDK or adb.
* iOS build / simulator / device — no macOS or Xcode.
* Native share sheets, iPad popover, receiving-app delivery, Photos/Files save.
* Real device encode performance, thermal behaviour, codec-specific colour
  shifts, and behaviour when the app is backgrounded mid-export.

The sample MP4s under `docs/samples/` were produced by a Python reference
renderer that mirrors the app's layout and timing constants; they are evidence
about the chosen container/codec/audio layout, **not** evidence that the app
builds or that the native plugins ran.

### Required device checks before claiming completion

1. `flutter pub get && flutter analyze && flutter test --concurrency=1 test packages/flutter_canvas_editor/test` on Flutter 3.47.7 / Dart 3.13.5.
2. Android device/emulator (API 24+): import a 10 s clip, export 15 s Story with music; verify with `ffprobe`/MediaInfo that it is H.264 + AAC, 450 frames, 1080 × 1920, 30 fps; confirm cancellation leaves no partial file.
3. Repeat for Square and Classic, and for the 540 × 960 quality option.
4. iOS 15+ device: same exports; confirm the second-pass mux keeps audio in sync and that the iPad share popover anchors to the Share button.
5. Share to at least two receiving apps (e.g. Files and a messaging app) and confirm the `.mp4` plays; do not infer delivery from the sheet opening.
6. Kill the app mid-export and confirm the draft and its media survive; delete a clip directory and confirm the "missing media" path.

## Known limitations

* One scene, 5–30 s, fixed 30 fps. No multi-scene sequencing, no per-layer
  keyframe tracks beyond one entrance and one exit.
* Music is **not audible in the in-app preview** (no audio-playback dependency
  was added); it is baked into the export only, and the transport bar labels it
  as such.
* Background video is converted to a JPEG proxy sequence at import time (bounded
  to 900 frames), so animation inside the clip is previewed at 30 fps from the
  proxy. Device storage use is shown in the settings sheet.
* Text animation supports opacity, translation and uniform scale only — no
  rotation, blur, masks or per-word effects.
* The export dialog's "Lighter file" option changes resolution and bitrate, not
  the frame rate.
* Sharing and gallery saving are OS actions; this project does not and cannot
  confirm that a recipient app accepted or delivered the file.
