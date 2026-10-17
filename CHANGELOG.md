# Unreleased

- Re-skinned the whole UI with the OpenDesign **premium** design system: warm canvas, graphite ink ramp, a single bronze accent, Cormorant Garamond / DM Sans, and adaptive desktop/tablet/mobile layouts.
- Replaced the fixed three-template list with a per-celebration catalogue: ten motifs drawn in six category palettes (60 designs), plus the nine original layouts kept so old drafts still open and export.
- Added a guided start (category → details → card) and one-tap whole-card video presets with slow ambient looping motion.
- Enlarging a field now re-stacks the linked wording into one column so it never overlaps the field below or leaves the page.
- Bundled a short generated tune per category and pre-select it when a project is created.
- Added real browser video export through `MediaRecorder` (silent WebM/MP4), alongside the native H.264/AAC encoders.
- Video edits (length, trim, fades, volume, per-layer motion) now share the same undo/redo history as image edits, with a slider drag coalesced into a single step.
- Honored the OS/browser "reduce motion" setting: applying an animation preset settles on the final frame instead of auto-playing.
- `flutter analyze` clean and the full test suite green on Flutter 3.47.7 / Dart 3.13.5.

# 1.0.0 — image-first implementation

- Integrated vendored BSD-3-Clause flutter_canvas_editor 1.2.0 into a real Flutter Android/iOS/web project.
- Added the live invitation form, template/format reflow, real canvas editing, typography/layer controls, undo/redo and responsive panels.
- Added original botanical, midnight and rosewater artwork with local OFL fonts and basic Arabic-script fallback/direction handling.
- Added actual 1×/2× PNG/JPEG generation, two-stage export/download, native share integration and app-documents saving.
- Added local drafts, editable JSON import/export, validation, quota/error visibility and host integration entry points.
- Hardened the editor’s export snapshot, bounds and resource ownership; corrected text alignment, image repaint/filtering, padding and first-drag behavior.
- Passed 58 Flutter tests, analyzer, a JavaScript web release build and 12 real-browser workflow checks.
- Native binaries/device sharing and MP4 are explicitly deferred, not represented as complete.
