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
| `lib/domain/invitation_template.dart` | Field IDs, original template layouts, formats, text fitting, font definitions |
| `lib/domain/project.dart` | Versioned project envelope and guarded JSON import |
| `lib/application/studio_controller.dart` | Serialized host edits, two-way field state, reflow, styling, layer actions, drafts and save status |
| `lib/services/draft_store.dart` | Replaceable `ProjectStore`; local preferences implementation and memory test implementation |
| `lib/services/export_service.dart` | Frozen-document PNG capture, filenames, dimensions and export metadata |
| `lib/services/jpeg_encoder_*.dart` | Conditional native/VM isolate encoding vs browser-native JPEG encoding |
| `lib/services/file_actions_*.dart` | Conditional app-documents/file-save vs Blob-download implementations |
| `lib/ui/` | Responsive Flutter workspace, panels, paper, thumbnail previews and export dialog |
| `packages/flutter_canvas_editor/` | Improved vendored editor; exact Dart diff in `tool/vendor_patch.diff` |
| `assets/` | Nine original 2× backgrounds, thumbnails and licensed local font files |
| `test/` | Host, document, export and responsive/gesture regression tests |
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

## Persistence and import security

`invita.project` version 1 stores project ID, title, UTC modification time and document JSON. Each project is independent of its flattened exports. Local preferences store at most 12 projects; opening a new one at capacity is blocked instead of silently dropping an old one.

Autosave is debounced by 650 ms and storage writes are serialized. Save-state revisions prevent an older write from falsely marking a newer pending edit saved. A write failure is visible and prompts a JSON backup. Lifecycle save attempts are best effort; a browser shutdown is not a transactional database commit.

Importer allowlists supported document sizes, the exact bundled background for that format, three local font families and background/text/image node types. Image layers may only reference embedded data URLs this app produced (`data:image/…;base64,…` within the size cap), must sit above the background and use a known box-fit. It rejects arbitrary URLs and filesystem paths, malformed IDs, duplicate IDs, missing linked fields, unbounded/invalid transforms, oversized input and excessive nodes/text/photos. The project envelope caps at 12 MB and each project at 50 nodes (≤8 photos, each ≤4 MB). This remains a portable template format, not a general asset container.

Preferences and browser storage are not encrypted or cross-device synchronization. Project exports contain personal invitation details in plain JSON. Hosting RSVP collection, backups/sync or accounts requires a separate product/security design.

## Native integration boundary

Android/iOS folders are real Flutter scaffolds with plugin dependencies and platform configuration. Android minimum SDK is 24; iOS deployment target is 15. Sharing uses `SharePlus.instance.share` with correctly typed PNG/JPEG files and a presentation origin. Mobile saving writes into app documents; the UI does not claim silent gallery writes.

Native builds, permissions/share actions, foreground/background behavior and receiver-app delivery require actual Android/iOS testing. They were not simulated by claiming web tests validate native plugins.

## Later MP4 work

Keep the editable document independent from output media. An animation increment should introduce explicit scene timing, deterministic interpolation/effects and a platform video compositor/encoder proof of concept. High-resolution frame buffers must be bounded. This source contains no video exporter, placeholder MP4 button, retired FFmpegKit binding or GPL FFmpeg dependency.
