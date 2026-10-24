# Unreleased

- **Event settings after creation.** The celebration is no longer locked to the wizard: a sheet changes it, explains what follows (wording defaults, bundled tune, which designs suit the card), and offers a matching design without losing typed words, photos or custom layers. Imported music is never replaced.
- **Duplicate draft and Save a copy.** The drafts list now shows "Wedding · edited 2 h ago" with per-draft actions; duplicating forks a new ID (the document ID follows) and opens the copy, while Save a copy writes the project JSON under a new name and leaves the draft alone.
- **Structured date and time.** Optional pickers write localized, formatted text into the existing `date`/`time` fields — which stay fully editable — and store the event separately as ISO data. From that: an RFC 5545 `.ics` file (octet-aware line folding), a Google Calendar link, and an RSVP QR code drawn on-device from a link the host supplies.
- **The card picker is now a catalogue.** Category tabs (For you / All designs / Favourites / Recent), a two-column thumbnail grid with motif and palette names, a larger preview of the applied design, starring that persists across drafts, and "Surprise me".
- **Fixed: a new project could not export video.** Every wizard project starts with a bundled tune (`tune_<category>`), but the export dialog looked music up with `loadAudio`, which only searches imported music, so the exporter aborted with "The music file for this draft is missing" — on the browser too, where the export is silent anyway. Bundled tunes now resolve through `loadBundledTune`, and the file is only required when it would actually be muxed (native and unmuted).
- **Fixed: tune lengths were invented.** `CategoryMusic` declared every tune as 12 s while the bundled WAVs run from 5.3 s to 8.5 s, so trim handles, fade limits and the "source length" label were wrong. `tool/generate_music.py` now writes a generated duration map from the WAV headers, the media services report it for bundled tunes, and a test compares the map with the files.
- **Fixed: the design picker contradicted the catalogue.** The panel said "Three original designs" while listing all 69 layouts, including the nine legacy ones. It now opens on `templatesFor(category)` with an "All designs" option over the sixty catalogue designs; legacy layouts stay resolvable but are no longer browsable.
- **Added: export preflight.** The export dialog now shows a checklist before rendering — artwork or clip present, music present or deliberately muted, browser silence, output size, frame count, estimated file size and time — with one-tap fixes (remove music, switch to silent, re-import clip) and a link to the video settings sheet, instead of failing at the end.
- **Cards come in three compositions.** `InvitationLayout` adds *Editorial* (a left column of tracked capitals over tall serif names, with the practical details stepped down in a quieter sans) and *Statement* (sans names, a wide-tracked announcement, more air) beside the original *Centred* stack. The sixty designs are spread across all three, so the catalogue is no longer one arrangement recoloured, and a new Composition control in the picker redraws the applied design in any of them as one undo step. Nothing extra is stored: `detectLayout` reads the arrangement back from the document's own geometry, so a format change, a reopen or an undo lands in the right composition, and a hand-moved card reports "unknown" instead of guessing.
- **The design picker scales instead of slowing down.** Its grid is now a lazy sliver list — only the rows on screen are built — and it renders 24 designs at a time with a "Show more" button, so a larger catalogue no longer builds sixty tiles and decodes sixty bitmaps before the user touches the screen. Thumbnails decode at their display width instead of the 360 px source, `DocumentPreview` decodes a 420 px thumbnail by default (the wizard shows ten previews at once; that step used to hold ~260 MB of decoded artwork), and `templateFor` answers from a background-asset index built once rather than rescanning 69 designs × 3 formats per lookup.
- The docs no longer pin a number of test cases (the catalogue scales the count); they cite the number of test files, which a consistency test checks against disk.
- Re-skinned the whole UI with the OpenDesign **premium** design system: warm canvas, graphite ink ramp, a single bronze accent, Cormorant Garamond / DM Sans, and adaptive desktop/tablet/mobile layouts.
- Replaced the fixed three-template list with a per-celebration catalogue: ten motifs drawn in six category palettes (60 designs), plus the nine original layouts kept so old drafts still open and export.
- Added a guided start (category → details → card) and one-tap whole-card video presets with slow ambient looping motion.
- Enlarging a field now re-stacks the linked wording into one column so it never overlaps the field below or leaves the page.
- Bundled a short generated tune per category and pre-select it when a project is created.
- Added real browser video export through `MediaRecorder` (silent WebM/MP4), alongside the native H.264/AAC encoders.
- Video edits (length, trim, fades, volume, per-layer motion) now share the same undo/redo history as image edits, with a slider drag coalesced into a single step.
- Honored the OS/browser "reduce motion" setting: applying an animation preset settles on the final frame instead of auto-playing.
- Improved screen-reader support: export progress and results are announced, the video sliders report their values with units, and the video preview exposes a descriptive label.
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
