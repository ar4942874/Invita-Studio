# Invita Studio

**A working Flutter invitation studio with an image editor and an animated video editor that exports real MP4 files—not a mockup or an embedded JavaScript editor.**

The app integrates a locally vendored, improved version of the open-source [flutter_canvas_editor 1.2.0](https://pub.dev/packages/flutter_canvas_editor/versions/1.2.0) engine (BSD-3-Clause). The surrounding invitation workflow, original artwork, export services and responsive Flutter interface are implemented in this project.

## What works now

- **Live invitation details:** names, date, time, venue, address, RSVP, opening line and invitation message update the real canvas. Canvas text edits and undo/redo update the form, too.
- **A design catalogue per celebration:** each category (wedding, engagement, birthday, anniversary, baby shower, other) offers ten designs, drawn as ten motifs in that category's palette. Switching designs preserves words and custom text; it replaces the linked fields’ arrangement and styling and can be undone.
- **Reflow on resize:** enlarging a field re-stacks the linked wording into a single column so it never overlaps the field below or leaves the page.
- **Three formats:** Classic 1080 × 1512, Story 1080 × 1920, Square 1080 × 1080. Format changes reflow linked fields and retain custom text.
- **Real canvas editing:** select, drag, resize, rotate, inline edit, add/delete custom text, arrange layers, center/straighten, change font, size, color, weight and alignment.
- **Undo/redo:** including atomic template/format changes and coalesced font-size slider changes. History is session-local, not serialized in project files.
- **High-resolution PNG and real JPEG:** 1× or 2×; up to **2160 × 3840** for Story. Export uses a frozen document snapshot, not a screenshot of the screen. Editing handles and viewport zoom are excluded.
- **Local drafts and portable projects:** debounced autosave, multiple drafts (up to 12), rename, import/export versioned editable JSON, and strict import validation.
- **Save/share plumbing:** browser Blob downloads; app-documents saving and `share_plus` native file sharing with an iPad share anchor. Native device behavior still needs validation.
- **Guided start:** a landing wizard picks the celebration category and its details, then the card, before the editor opens; each category pre-selects its bundled tune.
- **Video invitations (Android/iOS/web):** switch to **Video** to animate the same invitation. Play/pause, scrubbing, timecode, a ruler with per-layer tracks, 5–30 s length, visible windows, and fade / slide / zoom entrances and exits with duration, delay and easing. Import a background clip (trim, fit, loop) and optional music (trim, start offset, volume/mute, fades).
- **One-tap presets and ambient motion:** a preset strip styles the whole card (`fade`, `rise`, `zoom in/out`, `pop`, `slide`, "One by one", `none`) in a single tap, and a slow looping motion (`drift`, `zoom`, `breathe`) keeps the card alive across the whole clip. A `Customize` toggle still exposes the per-layer window, effect, duration and easing.
- **A tune per celebration:** every category ships a short bundled track that is pre-selected when you create the project; volume, fade and trim controls still apply.
- **Real MP4 export:** frames are rendered offscreen with the same painter as the preview, timestamped by frame index (never by playback time) and streamed one at a time to a native H.264 encoder (`MediaCodec` on Android, `AVAssetWriter` on iOS), with AAC music when enabled. 1080 × 1920 @ 30 fps for Story, 540 × 960 lighter option; Classic and Square keep their aspect ratio. Progress, cancellation, error reporting and partial-file cleanup are implemented. Silent and muted exports explicitly have **no audio track**.
- **Bundled fonts:** Cormorant Garamond, DM Sans and Noto Naskh Arabic. Basic first-strong direction detection and an Arabic-script fallback are included. No runtime font CDN.
- **Responsive UI:** desktop workspace, tablet layout and mobile editing sheets. No account, API key or backend is required.

**Status:** both editors run. On this project machine (Flutter 3.47.7 / Dart 3.13.5) `flutter analyze` is clean, the full Flutter test suite passes, and `flutter build web --release` succeeds. The browser build previews the animation (with music) and exports a real, **silent** WebM/MP4 through `MediaRecorder`. The native H.264/AAC encoders (`MediaCodec` on Android, `AVAssetWriter` on iOS) are implemented in source, but **no APK/IPA was built and no device encode, share sheet or device playback was executed** here. The sample MP4s in `docs/samples/` come from a Python reference renderer that mirrors the app's layout and timing — they validate the chosen container/codec/audio layout, not the app build. See [the video verification report](docs/VIDEO.md) and [QA](docs/QA.md) for the exact split between what was executed and what still needs a real device.

## Quick start

Validated SDK: **Flutter 3.47.7 / Dart 3.13.5**. This project’s SDK constraint requires Dart 3.13.5 or later within Dart 3.

```sh
flutter pub get
flutter run -d chrome
```

For a self-hosted web build, including its renderer resources:

```sh
flutter build web --release --no-web-resources-cdn --no-wasm-dry-run -O1
python3 tool/serve.py --directory build/web --port 8080
```

Open port 8080 in a browser. The server binds to `0.0.0.0`, accepts preview hosts and does not block iframe embedding. It has no API backend. The verified release uses JavaScript/O1; disabling the extra Wasm dry run keeps builds practical in a 2 GB sandbox.

If you have the separate **Invita_Studio_Web.zip**, extract it and run:

```sh
cd Invita_Studio_Web
python3 -m http.server 8080 --bind 0.0.0.0
```

Do not open `web/index.html` or the compiled release with `file://`; Flutter assets need an HTTP origin. Local drafts are scoped to that browser/origin. Self-hosted assets do not by themselves constitute an audited installable/offline PWA.

### Android / iOS

```sh
flutter doctor -v
flutter devices
flutter run -d <device-id>
```

- **Android:** install a compatible Android SDK and JDK 17 or 21. The project uses Java 17 source/bytecode targets and minimum Android SDK **24** (required by the resolved preferences plugin). This sandbox had Java 11 and no Android SDK; an Android build was not attempted.
- **iOS:** build on macOS with Xcode and signing configured. Generated deployment target is **iOS 15**. File sharing/open-in-place and an add-only Photos usage description are configured. No iOS simulator or device build was possible here.
- Change the application/bundle IDs, signing, release icons and release settings as needed. The generated Android release configuration currently uses **debug signing**; replace it before distributing a production release.
- Saving on mobile currently writes **inside the app’s documents directory**, not silently into the gallery. Use Share to choose Files, Photos or another app if the OS offers those actions. Receiver support and delivery are not guaranteed.

## Use the editor

1. Open **Details** and replace the fictional sample details. Dates/times are free-form display text, so you can use your preferred language and format.
2. Choose **Templates**, or select Classic / Story / Square above the canvas.
3. Tap a text layer to select it; drag to position, use handles to resize/rotate, and tap it again to edit inline. On mobile use the bottom **Style** or **Layers** buttons.
4. Use the inspector to change typography and ink. With nothing selected, it styles both names. Linked invitation layers cannot be deleted; clear their text to hide them. Custom text can be deleted.
5. Switch to **Video** (header on desktop, above the canvas on mobile) to animate the same wording and layout. Play or scrub, select a layer in the timeline, then set its visible window and `In`/`Out` effect. **Video settings** (tune icon) controls length, background clip and music. **Export MP4** opens the encoder dialog.
6. Choose **Export → Create PNG/JPEG → Download/Save or Share**. Preparing the file before the final action preserves a fresh browser user gesture. Out-of-document text is flagged before image export.
7. Use **Project options → Export editable project** for a backup. Import with **Open project JSON**. A flattened PNG/JPEG or MP4 is not an editable project.

Video notes: imported clips and music are stored in the app's managed media directory, not inside the project JSON. Project JSON is therefore a layout/word backup — to move a video project to another device, copy `InvitaStudioMedia/<projectId>/` with it. Missing media is reported in the preview and the settings sheet instead of crashing. Each celebration also ships a bundled tune that is pre-selected when you create the project, so no import is needed. Music is audible in the browser preview (the browser download stays silent) but not in the native in-app preview (no audio-playback plugin was added); native export muxes it into the MP4. The browser exports a real, **silent** WebM/MP4 through `MediaRecorder`; desktop can preview and edit timing but cannot encode, and the dialog says so instead of faking an export.

Long form values shrink to the existing text area without truncation. After substantially shortening a previously long value, use the size control or Reset layout to grow the text again. Manual edits can still cause visual overlaps; inspect the preview. Reset layout removes custom text and restores the linked layout/styles, but can be undone.

## Integrate into an existing Flutter app

No existing app was supplied, so this repository is a runnable Flutter application. The implementation is separated so it can also be moved into a host app:

1. Copy `lib/application`, `lib/domain`, `lib/services`, `lib/ui`, and `lib/invitation_studio.dart` into a feature directory, keeping their relative layout. Do **not** overwrite the host’s existing `main.dart`.
2. Copy `assets/` and `packages/flutter_canvas_editor/`; merge the dependencies, assets and font registrations from `pubspec.yaml` into the host. Keep the three font-family aliases unchanged. Update the path dependency/import prefix for your layout.
3. Merge the Android/iOS requirements above and preserve all licenses. Asset names currently refer to the **host app’s** `assets/art/` and `assets/fonts/`; this is not yet a separately published package with package-prefixed assets.
4. Initialize local fonts and register their licenses once during app bootstrap, then open the screen with a host-owned controller:

```dart
import 'package:flutter/material.dart';
// Adjust this import to where you copied the feature.
import 'package:your_app/features/invitation/invitation_studio.dart';

Future<void> openInvitationStudio(BuildContext context) async {
  await loadStudioFonts();
  // Prefer registering once in the host's bootstrap, not on every route open.
  registerStudioFontLicenses();
  final studio = await StudioController.restore();
  if (!context.mounted) {
    studio.dispose();
    return;
  }
  try {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Theme(
        data: studioTheme(),
        child: StudioScreen(studio: studio),
      ),
    ));
  } finally {
    await studio.flush();
    await studio.saveNow();
    studio.dispose();
  }
}
```

`StudioController`, `StudioProject`, `InvitationTemplate`, `ExportService`, `ProjectStore` and `StudioScreen` are exported by `lib/invitation_studio.dart`. Replace `ProjectStore` if you later need a database or authenticated synchronization.

## Verify

```sh
flutter analyze
flutter test --concurrency=1 test packages/flutter_canvas_editor/test
flutter build web --release --no-web-resources-cdn --no-wasm-dry-run -O1

# Start the compiled web server first, then run real-browser checks:
npm ci --prefix tool/browser
npx --prefix tool/browser playwright install --with-deps chromium
node tool/browser/smoke.cjs
node tool/browser/photo.cjs
```

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs the first three commands on the pinned SDK (Flutter 3.47.7) for every push and pull request. The suite includes [`test/docs_consistency_test.dart`](test/docs_consistency_test.dart), which fails if these docs drift from the code (stale claims, SDK version, web palette, cited suite size).

**Recorded result:** on the project machine (Flutter 3.47.7 / Dart 3.13.5) `flutter analyze` is clean and the full test suite passes — including the video model and exporter tests (see [QA](docs/QA.md) for the current count). **12 browser workflow checks** and **7 photo-card browser checks** passed against the compiled web build (recorded on the image-editor baseline; the scenarios they exercise are unchanged). Native Android/iOS compilation and device runs remain unexecuted. Actual downloaded PNG/JPEG signatures and dimensions were independently decoded and checked. The browser tests include live editing, photo import/styling/export, reflow, JSON backup/import, reload persistence, mobile editing/export, sharing-unavailable handling and operation without external network dependencies. See [QA results](docs/QA.md), [architecture](docs/ARCHITECTURE.md), and `docs/qa/` for evidence.

## Important boundaries

- The image editor edits text and your own photos over bundled artwork. Photos are downscaled (≤1600 px), re-encoded as bounded data URLs and embedded in the project; filters, freehand drawing, QR generation, cloud sync, hosted RSVP collection and PDF/CMYK/bleed workflows are **not implemented**.
- The video editor is single-scene, 5–30 s at a fixed 30 fps, with one entrance and one exit per layer (opacity, translate, uniform scale). It is not a multi-scene NLE and has no keyframe tracks, masks, rotation animation or per-word effects.
- MP4 export runs natively on Android/iOS and, silently, in the browser (WebM/MP4 via `MediaRecorder`). Desktop can preview and edit timing but cannot encode, and the UI says so. No Android/iOS binary, device encode, share-sheet or delivery test is claimed in this branch.
- Portable JSON projects do **not** bundle imported video or music; media must be relinked on another device. The MP4 is written to the app documents directory and handed to the system share sheet — saving to Photos/Gallery is an OS action, not something this app can confirm.
- RSVP and location are display text, not a backend or response-collection service.
- Browser sharing requires browser/OS support and a permitted secure context. If unavailable, the UI directs the user to download. Native sharing is wired, not device-certified.
- Drafts use local preferences/browser storage, **not encrypted cloud storage**. Clearing app/browser data, storage eviction, private-mode restrictions, quota limits or abrupt closure can lose drafts, including very recent debounced edits. Export JSON backups for important work.
- Project import permits only bundled assets, embedded photos this app created, approved fonts, supported formats, bounded transforms/text and at most 50 total nodes (including ≤8 photos, each ≤4 MB). Arbitrary URLs, filesystem paths and custom node types are rejected; project files cap at 12 MB.
- Basic Arabic-script direction/fallback is not a full multilingual typography or accessibility certification. Validate your final wording and fonts on target devices.

## Open-source provenance

App code and original artwork: **MIT**, except third-party components. The vendored engine and its local modifications remain **BSD-3-Clause**; the fonts retain **SIL OFL 1.1**. Full notices and upstream provenance are retained. No unlicensed invitation-app code, proprietary editor, FFmpeg binary or GPL video dependency was copied in. The video pipeline adds **no new package dependency**: it uses the already-present `path_provider`, `file_selector` and `share_plus`, and the platform H.264/AAC encoders shipped with Android and iOS. The Python reference renderer in `tool/reference_sample.py` is a development aid only (Pillow + imageio-ffmpeg are not app dependencies).

See [third-party notices](THIRD_PARTY_NOTICES.md), `packages/flutter_canvas_editor/UPSTREAM.md`, its original `LICENSE`, the exact local `tool/vendor_patch.diff`, and `assets/fonts/*-OFL.txt`. Original artwork is reproducibly generated by `tool/generate_art.py` (optional Pillow dependency); it is already bundled.

## Next increment

The next step is verification, not more surface area: build on a real Android device (API 24+) and an iOS 15+ device, export Story/Square/Classic at both qualities, inspect the files with `ffprobe`/MediaInfo, test cancellation and app-kill recovery, and exercise the share sheet into at least two receiving apps. Then replace the debug signing configuration and choose final app IDs. After that, consider multi-scene sequencing and richer per-layer animation. See [docs/VIDEO.md](docs/VIDEO.md#required-device-checks-before-claiming-completion).
