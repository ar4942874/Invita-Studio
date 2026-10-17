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
| Card presets | `MotionPreset` in `lib/domain/video/timeline.dart` gives a layman one-tap, whole-card styles — `fade`, `rise`, `zoomIn`, `zoomOut`, `pop`, `slide`, `stagger` ("One by one") and `none`. Each writes ordinary per-layer motions, so preview and export need no special case, and `MotionPreset.detect` re-highlights the style a timeline currently matches. `VideoTimeline.settledTimeMs` reports when every entrance has finished so an idle preview shows the settled card instead of a blank first frame. |
| Looping motion | `AmbientMotion` (`none`, `drift`, `zoom`, `breathe`) applies one slow transform to **every** layer for the whole card. Entrances only occupy the first second, so without a looping motion the export was effectively a still image for the rest of its length. Applying a preset sets a matching looping motion (`zoomIn`/`zoomOut` → `zoom`, `rise`/`slide`/`stagger` → `drift`, `fade`/`pop` → `breathe`); the workspace header offers an override. |
| Preview | Play/pause, scrubbing, timecode, ruler, layer tracks and playhead. The default workspace shows a preset strip so a non-technical user just taps a style; a `Customize` toggle reveals the per-layer inspector for window/effect/duration/easing. Frame painting goes through `TimelineFrameRenderer`. |
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
    ├── ambient (none | drift | zoom | breathe)
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

| Platform | Preview + timeline editing | Background-clip import | Video export |
|---|---|---|---|
| Android 7+ (minSdk 24) | yes | yes (native, on disk) | yes (native H.264 + AAC MP4) |
| iOS 15+ | yes | yes (native, on disk) | yes (native H.264 + AAC MP4) |
| Web | yes (music plays in the preview) | yes — decoded in memory for the session, not persisted | yes — `MediaRecorder` downloads WebM/MP4, always silent |
| Desktop | yes (artwork, animations, scrubbing) | no | no — dialog explains the encoder is unavailable |

Desktop never pretends to export: `isVideoExportSupported` gates the action and
the dialog explains that preview and timing still work.

## Web build (browser)

The browser has no filesystem and no platform codec plugins, so two seams are
swapped behind conditional imports:

* **Export** — `video_encoder_platform.dart` selects
  `video_encoder_web.dart`, which records the rendered canvas through
  `MediaRecorder` over `canvas.captureStream(fps)` paced to real time. The
  canvas is attached offscreen (some engines only capture attached canvases),
  the recorder is warmed up before frame 0 and the final frame is held before
  stopping; manual `requestFrame()` capture was dropped because some browsers
  ignore it and produced a still video. `VideoExporter` skips the temp file,
  `rename` and audio muxing on the web (`kIsWeb` guards) and downloads the
  resulting blob through `saveBytes` (File System Access API → `window.open` →
  anchor fallback). Output is WebM on Chromium/Firefox and MP4 on
  Safari/newer Chromium, and is **always silent**.
* **Background-clip import** — `video_media_platform.dart` selects
  `video_media_service_web.dart`, which probes a picked file with a `<video>`
  element and extracts downscaled frames (seek + `drawImage` + PNG encode),
  holding them in memory for the session. Reloading the page loses them; the
  draft then reports the clip as missing and the settings sheet offers re-import.
* **Music import + preview playback** — `video_media_service_web.dart` probes a
  picked file with an `<audio>` element (for its duration), keeps the bytes in
  memory and hands back a blob object URL. `video_audio_platform.dart` selects
  `video_audio_player_web.dart`, which drives an `<audio>` element from the
  transport and applies the trim start, volume and fade-in/fade-out envelope, so
  music is **audible in the web preview**. The browser export stays silent, so
  the download has no audio track. Native builds use a no-op player
  (`video_audio_player_native.dart`) because the encoder muxes the music instead;
  desktop disables music import.
* **Bundled category tunes** — `lib/domain/category_music.dart` names one WAV per
  celebration (`assets/music/tune_<category>.wav`, asset IDs prefixed `tune_`).
  `loadBundledTune` resolves those IDs straight from the app bundle instead of
  managed storage: the web hands back a blob object URL for the preview player,
  and native copies the bytes into the project's audio folder so the encoder can
  mux them. Creating a project pre-selects the matching tune, so music is present
  without an import step. Each tune's length comes from a generated map
  (`category_music_durations.g.dart`, written by `tool/generate_music.py` from the
  WAV headers), because trim handles, fade limits and the preflight all need the
  real length rather than a fixed guess.

**Which audio an export actually needs.** `lib/services/video/export_media.dart`
owns the single rule: the music file is required only on a native build with an
unmuted track. A browser export is silent by construction, and a muted track is
written without an audio track, so neither may fail for a missing file. The same
module routes `tune_*` IDs through `loadBundledTune` — resolving a bundled tune
with `loadAudio` is what used to abort every first-run browser export.
`lib/services/video/export_preflight.dart` turns the same inputs into the
checklist the export dialog shows before rendering (background present, music
present or deliberately muted, browser silence, dimensions, frame count,
estimated size and time), with one-tap fixes.

`ImportedClip.readFrame` abstracts the frame source: native reads JPEG files
from the managed directory, the browser returns in-memory PNG bytes.

## Verification

### Executed in this environment

| Check | Result |
|---|---|
| Dart syntax parse of all 71 repo `.dart` files with the `tree-sitter-dart` (orchard) grammar | 1 pre-existing ambiguity in a vendored controller file (ternary/function-type parse), 0 errors in the new or modified files |
| Reference render of a 15 s / 1080 × 1920 / 30 fps invitation (artwork + 10 animated layers) | Playable MP4; ffmpeg decodes **450 video frames**, duration **15.00 s** |
| Silent and music variants | Silent variant has no audio stream; music variant has AAC-LC 44.1 kHz stereo, mean volume −23.2 dB, peak −13.6 dB |
| Container flags | `ftyp isom`, `moov` before `mdat` (fast start), bt709 colour tags |
| Project JSON round-trip / v1 migration / validation tests | `test/video_project_test.dart` — pass on Flutter 3.47.7 / Dart 3.13.5 |
| Timeline evaluation, easing, frame-index tests | `test/video_timeline_test.dart` — pass |
| Media/manifest/frame-mapping/progress tests | `test/video_media_test.dart` — pass |
| Full suite (19 test files), web export/import/music wiring | `flutter analyze` clean, `flutter test` all pass, `flutter build web --release` succeeds |

### Not executed (needs a real device or macOS/Windows toolchain)

The Dart-side pipeline above was run and passes on Flutter 3.47.7 / Dart 3.13.5;
the following each need hardware or a toolchain this environment does not have:

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

1. Re-run `flutter pub get && flutter analyze && flutter test --concurrency=1 test packages/flutter_canvas_editor/test` on Flutter 3.47.7 / Dart 3.13.5 against the release commit (currently analyzer-clean with the full suite green; read the executed case count from the run itself, it is not pinned here).
2. Android device/emulator (API 24+): import a 10 s clip, export 15 s Story with music; verify with `ffprobe`/MediaInfo that it is H.264 + AAC, 450 frames, 1080 × 1920, 30 fps; confirm cancellation leaves no partial file.
3. Repeat for Square and Classic, and for the 540 × 960 quality option.
4. iOS 15+ device: same exports; confirm the second-pass mux keeps audio in sync and that the iPad share popover anchors to the Share button.
5. Share to at least two receiving apps (e.g. Files and a messaging app) and confirm the `.mp4` plays; do not infer delivery from the sheet opening.
6. Kill the app mid-export and confirm the draft and its media survive; delete a clip directory and confirm the "missing media" path.

## Known limitations

* One scene, 5–30 s, fixed 30 fps. No multi-scene sequencing, no per-layer
  keyframe tracks beyond one entrance and one exit.
* Music plays in the **web** preview through an `<audio>` element (trim start,
  volume and fades are applied). Native builds have no audio-playback dependency,
  so there it is baked into the export only and is not audible in the preview;
  the transport bar labels the native case as such. On the web the music is
  previewed only — the browser export is silent.
* Background video is converted to a JPEG proxy sequence at import time (bounded
  to 900 frames), so animation inside the clip is previewed at 30 fps from the
  proxy. Device storage use is shown in the settings sheet. On the web the proxy
  is decoded into memory for the session only (no persistence) and exported
  video stays silent; the browser build targets current Chrome, Edge, Firefox and
  Safari.
* Text animation supports opacity, translation and uniform scale only — no
  rotation, blur, masks or per-word effects.
* The export dialog's "Lighter file" option changes resolution and bitrate, not
  the frame rate.
* Sharing and gallery saving are OS actions; this project does not and cannot
  confirm that a recipient app accepted or delivered the file.
