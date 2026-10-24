# Architecture and implementation notes

## Deliberate foundation

The actual canvas is the vendored BSD-3-Clause `flutter_canvas_editor` 1.2.0 engine, not a WebView or a facsimile canvas built only for the screenshot. It owns the design document, hit testing, transforms, selection, inline editing, BLoC state and document undo/redo. Its upstream license and provenance are retained in `packages/flutter_canvas_editor/`.

The host is a Flutter application with a `ChangeNotifier` coordinator. No second BLoC/state framework was added to the host. There is no server, authentication layer, tracking SDK or invitation data API.

## Structure

| Path | Responsibility |
|---|---|
| `lib/main.dart` | Binding, local font/license bootstrap, draft restore, initial artwork warm-up |
| `lib/app.dart` | Standalone Material app |
| `lib/invitation_studio.dart` | Public host integration exports |
| `lib/domain/invitation_template.dart` | Field IDs, formats, text fitting, font definitions and the design catalogue (10 motifs × 6 category palettes = 60 designs, plus 9 legacy layouts) |
| `lib/domain/category_music.dart` | The bundled tune each celebration starts with, as a `VideoAudio` with the `tune_` asset prefix |
| `lib/domain/project.dart` | Versioned project envelope (schema 2), v1 migration, guarded JSON import, effective video view |
| `lib/domain/video/timeline.dart` | Flutter-free video model: duration, background clip, layer windows/effects, music, deterministic evaluation |
| `lib/services/video/frame_renderer.dart` | Shared preview/export painter, clipped background-frame LRU, export frame feed |
| `lib/services/video/video_media.dart` | Managed media storage, clip manifests, native probe/extraction channel and the `VideoMediaService` interface |
| `lib/services/video/video_media_platform.dart` | Conditional native/browser `VideoMediaService` factory |
| `lib/services/video/video_encoder.dart` | Encoder spec/session interface (`EncodedVideo` result) and the native `invita/video_export` backend |
| `lib/services/video/video_encoder_platform.dart` | Conditional native/browser `VideoEncoderBackend` factory (`MediaRecorder` on the web) |
| `lib/services/video/video_audio_player*.dart` | Conditional preview-music player: `<audio>` on the web, no-op on native |
| `lib/services/video/video_export_service.dart` | Frozen-snapshot exporter, progress, cancellation, temp cleanup |
| `lib/ui/video/` | Video workspace, preview, transport, settings sheet and MP4 export dialog |
| `lib/application/studio_controller.dart` | Serialized host edits, two-way field state, reflow, styling, layer actions, drafts and save status |
| `lib/services/draft_store.dart` | Replaceable `ProjectStore`; local preferences implementation and memory test implementation |
| `lib/services/export_service.dart` | Frozen-document PNG capture, filenames, dimensions and export metadata |
| `lib/services/jpeg_encoder_*.dart` | Conditional native/VM isolate encoding vs browser-native JPEG encoding |
| `lib/services/file_actions_*.dart` | Conditional app-documents/file-save vs Blob-download implementations |
| `lib/ui/` | Responsive Flutter workspace, panels, paper, thumbnail previews and export dialog |
| `lib/ui/home_screen.dart` | Landing wizard: pick a celebration category, enter the details, choose a card, then open the editor |
| `packages/flutter_canvas_editor/` | Improved vendored editor; exact Dart diff in `tool/vendor_patch.diff` |
| `assets/` | 9 legacy and 60 category 2× backgrounds, thumbnails, 6 synthesized category tunes and licensed local font files |
| `test/` | Host, document, export and responsive/gesture regression tests |
| `tool/generate_art.py`, `tool/generate_category_art.py`, `tool/generate_music.py` | Deterministic PIL backgrounds and numpy tunes (no external assets) |
| `tool/browser/` | Real-browser workflow checks against the compiled Flutter app |

## Canonical state and ordering

Text nodes are the source of truth. Stable IDs bind the guided fields to their canvas nodes; the project does not maintain a second stale copy of names/date/venue. The ampersand is also an editable linked text node. Custom text uses `extra.*` IDs.

Host operations are serialized through a queue. Pending field values remain visible while an older update is being applied, so a previous BLoC emission cannot overwrite newer keystrokes. The fork’s awaitable `applyDocument` acknowledges application of a complete change. Template/format changes therefore replace related nodes atomically without resetting undo history.

The host listens to the live editor state stream, not just committed changes, so drag and inline edits update the document and autosave state. Font-size slider updates open and commit a history session. Engine gestures/inline editing commit their own snapshots. Opening a different project intentionally resets session history.

Template changes retain linked values and custom text but restore the new design’s linked layout/styles. Format changes use fresh linked slots, retain style choices proportionally and transform custom text vertically. Reset layout deliberately removes custom text; the UI warns and the operation can be undone.

## Rendering and image ownership

Original backgrounds are rasterized at exactly 2× each supported format by `tool/generate_art.py`. They contain ornament only; invitation wording remains editable text.

The live editor, selection-free PNG exporter and host share the same document/font/asset references. Passive thumbnail previews use the same frames, strings, styles and transforms but are not interactive editors. Custom widget nodes are not supported by the app because upstream PNG export does not render those widgets.

Provider images are cloned before a canvas/export owns their handles. Received `ImageInfo`, local codecs, temporary pictures, text painters and owned images are disposed. Late loads after widget teardown are disposed, and unused live-canvas asset handles are pruned. The Flutter image cache may still retain its own independent handles.

The painter now lays out text at the full frame width, which is necessary for real center/right alignment. The host supplies zero engine padding inside its own paper frame. Viewport zoom is outside the document/export path.

## Visual system

The whole UI is themed from the OpenDesign **`premium`** design system (open-design/design-systems/premium). The design contract lives in `lib/ui/studio_theme.dart`: token names (`StudioColors`, `StudioShape`, `StudioMotion`, `StudioShadows`, `StudioType`, `studioPageGradient`) deliberately mirror the package's CSS custom properties so the app can be re-skinned from another OpenDesign package by editing one file.

The palette is a warm-white canvas (`#FAF8F4`) with a graphite ink ramp and a muted bronze accent (`#A06A3B`) as the single signal colour; status uses the package's success/warn/danger tokens rather than ad-hoc hex values. Widgets consume the tokens instead of hard-coding colours.

The package names the commercial typefaces *Canela* (display) and *Inter* (body). Because neither is redistributable, the app substitutes the bundled OFL families **Cormorant Garamond** and **DM Sans**, which share the same display/body roles and keep the build offline and portable.

One deliberate exception: the home screen lays on a second OpenDesign package, **`elegant`** (open-design/design-systems/elegant). Its token contract lives in `lib/ui/home_theme.dart` (`HomeColors`, `HomeShape`, `homePageGradient`, `elegantHomeTheme()`), which wraps `HomeScreen` in a scoped `Theme` so the landing wizard — warm ivory canvas, cacao accent `#9B5B32`, serif-led headings — reads as its own first impression while buttons, inputs and popups pick up the same package. The editor chrome above it stays entirely on `premium`.

## Category catalogue, music and reflow

The card step offers ten designs per celebration. A design is a *motif* drawn in a *category palette*: ten hand-written motifs (botanical, celestial, petals, foil frame, arches, confetti, clouds, constellation, laurel, sunburst) are rendered once per celebration palette by `tool/generate_category_art.py`, producing sixty 2× backgrounds and their thumbnails. Because a design carries no template-specific layout, all sixty share the same linked text slots; the nine original designs remain in the catalogue only so older drafts still resolve and export, and `templateFor` matches the exact background asset rather than a name prefix. `invitationTemplates` is therefore the full render list (60 designs, plus 9 legacy layouts) that the asset allowlist and image provider derive from, while `catalogueTemplates` is what the studio picker may show: the in-editor panel lists `templatesFor(category)` first and offers "All designs" over the sixty, and legacy layouts are reachable only through the asset resolver. The home wizard and the panel therefore never disagree about what the catalogue contains. The in-editor picker is a grid with tabs (For you / All designs / Favourites / Recent), a preview of the applied design and "Surprise me"; favourites and recently-used IDs live in `CatalogPrefs` (shared preferences), not in the project, because they describe the person rather than one invitation. `StudioController.chooseTemplate` records recency for every entry point, including the wizard.

The picker is built to grow. Its grid is a `CustomScrollView` whose rows are a `SliverList`, so only the rows on screen exist and a tile costs nothing until it is scrolled into view; each page renders 24 designs and a "Show more" button adds the next 24 (the count and "Surprise me" still work over the whole slice). Thumbnails decode at their display width (`cacheWidth`, capped at the bundled 360 px source) rather than at full size: sixty full-size thumbnails would hold ~43 MB of decoded bitmaps before the first scroll. The same rule now applies to `DocumentPreview`, which the wizard uses for ten live cards and the panels for 34–70 px rows — it decodes a 420 px thumbnail by default and callers that need a large preview pass `decodeWidth` explicitly. `templateFor` answers from an asset→design index built once, and `invitationArtAssets` (with `invitationArtAssetsFor`) is the single allowlist the image provider and the importer share instead of rebuilding 207 strings per call.

Each celebration also ships a short synthesized tune (`tool/generate_music.py`, 16 kHz mono WAV) at `assets/music/tune_<category>.wav`. `CategoryMusic` turns the category into a normal `VideoAudio` whose asset ID carries the `tune_` prefix; the media services resolve that prefix from the app bundle instead of managed storage (`loadBundledTune`), so the tune needs no import step. Declared lengths are generated from the WAV headers into `lib/domain/category_music_durations.g.dart` rather than hard-coded, so trim bounds and the export preflight use the real track length. Creating a project pre-selects it. On the web it plays through the preview player while the browser export stays silent; on native the bytes are copied into the project's audio folder and muxed into the MP4.

Text stays legible when a field is enlarged: `StudioController._reflowStack` re-stacks the linked wording into a single vertical column, keeping each field's horizontal placement while pushing siblings down, then shifting the column up and compressing gaps until it fits inside the page margins. The font-size slider drives it, so increasing one field never overlaps the next.

## Export path

1. Unfocus inline editing and flush queued host edits before opening export.
2. Flag text whose transformed glyph bounds extend beyond the paper. This is not a full collision/overlap detector.
3. Capture an immutable document snapshot before the first asynchronous image wait.
4. Validate dimensions and pixel ratio; cap allocation at 16,777,216 output pixels. The UI exposes only 1× and 2×.
5. Load referenced images, fail if an image is missing, then paint without selection into a `ui.Picture` and encode PNG.
6. For JPEG, composite onto white and encode real JPEG: `image` in a separate VM isolate on native targets; Canvas/ImageBitmap/Blob APIs in the browser. Unsupported browser JPEG encoding reports a failure rather than returning mislabeled PNG.
7. Retain the generated bytes in the dialog. A separate Download/Save/Share click supplies a fresh user gesture. Share calls provide a real button rectangle for iPad presentation.
8. Dispose temporary native image/picture handles in `finally`.

The result is independent of physical screen dimensions and viewport zoom. This is not a print-prepress or cross-platform pixel-identical typography guarantee.

## Invitation actions

The `date` and `time` fields are the card's prose and stay free text. Next to them, optional pickers write a localized, formatted string into those same fields *and* store the event as `EventDateTime` (calendar date plus optional hour/minute). Nothing is inferred from the prose, so a host who types "Reception at 7:00 in the evening" keeps exactly that.

Everything downstream is pure string work in `lib/services/invite_actions.dart`:

* `buildIcs` writes an RFC 5545 `VEVENT` with CRLF endings, escaped text and octet-aware folding at 75 bytes — an Urdu summary folds on bytes, not characters, so strict parsers accept it. Times are floating (no `TZID`): the picker captured a wall-clock time, not an instant in a zone.
* `googleCalendarUrl` builds a `TEMPLATE` link with the same details, opened through `url_launcher` and copied to the clipboard when no handler answers.
* `isValidRsvpUrl` gates the RSVP field to absolute `http(s)` URLs; the code itself is drawn on-device with `package:qr` (`QrCodeView`), so no link ever leaves the app to be rendered.

The structured event travels in the project JSON, so a reopened draft still has its calendar and RSVP actions.

## Persistence and import security

`invita.project` version 1 stores project ID, title, UTC modification time and document JSON. Schema 2 adds the video timeline and, additively, a celebration `category` (older files without the key load as `wedding`), a structured `when` (`{date, hour, minute}`, floating local time) and an optional `rsvpUrl`. All three are optional: a draft typed as prose still opens, and the calendar/RSVP actions stay hidden until a date exists. Each project is independent of its flattened exports. Local preferences store at most 12 projects; opening a new one at capacity is blocked instead of silently dropping an old one.

Autosave is debounced by 650 ms and storage writes are serialized. Save-state revisions prevent an older write from falsely marking a newer pending edit saved. A write failure is visible and prompts a JSON backup. Lifecycle save attempts are best effort; a browser shutdown is not a transactional database commit.

Importer allowlists supported document sizes, the exact bundled background for that format, three local font families and background/text/image node types. Image layers may only reference embedded data URLs this app produced (`data:image/…;base64,…` within the size cap), must sit above the background and use a known box-fit. It rejects arbitrary URLs and filesystem paths, malformed IDs, duplicate IDs, missing linked fields, unbounded/invalid transforms, oversized input and excessive nodes/text/photos. The project envelope caps at 12 MB and each project at 50 nodes (≤8 photos, each ≤4 MB). This remains a portable template format, not a general asset container.

Preferences and browser storage are not encrypted or cross-device synchronization. Project exports contain personal invitation details in plain JSON. Hosting RSVP collection, backups/sync or accounts requires a separate product/security design.

## Video timeline and export

Video mode is a second **view over the same document**, not a second project. `StudioController` keeps one `DesignDocument`; `StudioProject` gains a `video` field (schema 2) whose layer keys are existing node IDs. Edits made in either mode therefore update the other instantly, and no field data is duplicated.

`VideoTimeline` is deliberately Flutter-free and versioned. `evaluateTimeline(timeline, layerIds, timeMs)` is the only animation evaluator; it returns opacity, offset and uniform scale per layer. The same function feeds the live preview and the exporter. Entrance effects settle at their neutral value; exits run the same effect away from it. Layers without an entry are visible for the whole timeline. An optional `AmbientMotion` (`drift`, `zoom`, `breathe`) adds one slow looping transform to every layer across the full duration, so a card keeps moving after its entrances settle instead of reading as a still image.

`MotionPreset` (same file) sits above that model: the layman UI applies a named whole-card style (`fade`, `rise`, `zoomIn`, `zoomOut`, `pop`, `slide`, `stagger`, `none`) and the preset method expands it into ordinary per-layer `LayerMotion` values plus a matching `AmbientMotion`. Because it only writes the shared model, neither the preview nor the exporter knows presets exist. `MotionPreset.detect` compares a timeline back to each preset so the gallery can show which style is active.

`TimelineFrameRenderer.paintFrame` is shared by the preview (`VideoFramePainter`) and the exporter (`renderImage` → raw RGBA):

1. the background node (bundled artwork and its colour),
2. the fitted imported clip frame (cover/contain/fill matches photo-layer maths),
3. animated layers painted by `CanvasPainter` with per-node opacity.

The engine's only change is opt-in: `nodeOpacities` wraps a layer in `saveLayer` only when it is actually translucent. Static editing is unchanged.

### Determinism and memory

Export timestamps are `frameIndex * 1e6 ~/ fps`; wall-clock playback is confined to `VideoPlaybackController`, which only drives the UI. The exporter copies the node list and motion map before its first `await`, renders one frame at a time, awaits the native `addFrame` before rendering the next, and keeps at most two decoded background frames. Cancellation is checked between frames; failures delete the partial file and dispose images in `finally`.

### Native services

Two platform channels sit behind plain Dart interfaces, and both are reached
through conditional factories so the browser uses a pure-Dart implementation
instead:

* `invita/video_media` — probe video/audio, extract a bounded JPEG proxy sequence (≤900 frames, ≤1080×1920) with progress and cancellation. `VideoMediaService` (`createVideoMediaService()`) wraps it and the managed store.
* `invita/video_export` — open a session, `addFrame` (RGBA8888 + timestamp), `finish`, `cancel`. `finish` returns an `EncodedVideo` (path + byte count) so the browser backend can hand back a downloaded blob instead of a file path.

Android implements the encoder with `MediaCodec`/`MediaMuxer` (H.264 Baseline preferred, AAC-LC 128 kb/s) and applies music trim/gain/fades while decoding to PCM. iOS uses `AVAssetWriter` and, for music, an `AVMutableComposition` second pass with passthrough when no gain/fade is needed. Desktop has no encoder: `isVideoExportSupported` is false and the dialog explains that only preview/editing is available.

On the web, `video_encoder_web.dart` records the rendered canvas through `MediaRecorder` at `captureStream(fps)` (canvas attached offscreen, recorder warmed up before frame 0, final frame held before stop) and downloads it via `saveBytes`, and `video_media_service_web.dart` decodes a picked clip into in-memory PNG frames for the session (`ImportedClip.frameReader`). Imported music is probed with an `<audio>` element, kept in memory and previewed by `video_audio_player_web.dart` (trim start, volume, fades); the browser export stays silent. `VideoExporter` guards the temp file, rename and audio muxing with `kIsWeb`.

Imported media lives under `<documents>/InvitaStudioMedia/<projectId>/` with a JSON manifest per clip. Project JSON stores IDs and trims only, so projects stay small; the trade-off is that portable JSON does not carry media and must be relinked, and browser imports are not persisted at all. Missing media is a first-class state in the preview and settings sheet.

## Native integration boundary

Android/iOS folders are real Flutter scaffolds with plugin dependencies and platform configuration. Android minimum SDK is 24; iOS deployment target is 15. Sharing uses `SharePlus.instance.share` with correctly typed files and a presentation origin. Mobile saving writes into app documents; the UI does not claim silent gallery writes.

The video plugins are registered explicitly: `MainActivity.configureFlutterEngine` attaches both Kotlin handlers, and `AppDelegate.didInitializeImplicitFlutterEngine` registers both Swift plugins. Native builds, permissions/share actions, foreground/background behavior and receiver-app delivery require actual Android/iOS testing. They were not simulated by claiming web tests validate native plugins.

