# 1.0.0 — image-first implementation

- Integrated vendored BSD-3-Clause flutter_canvas_editor 1.2.0 into a real Flutter Android/iOS/web project.
- Added the live invitation form, template/format reflow, real canvas editing, typography/layer controls, undo/redo and responsive panels.
- Added original botanical, midnight and rosewater artwork with local OFL fonts and basic Arabic-script fallback/direction handling.
- Added actual 1×/2× PNG/JPEG generation, two-stage export/download, native share integration and app-documents saving.
- Added local drafts, editable JSON import/export, validation, quota/error visibility and host integration entry points.
- Hardened the editor’s export snapshot, bounds and resource ownership; corrected text alignment, image repaint/filtering, padding and first-drag behavior.
- Passed 58 Flutter tests, analyzer, a JavaScript web release build and 12 real-browser workflow checks.
- Native binaries/device sharing and MP4 are explicitly deferred, not represented as complete.
