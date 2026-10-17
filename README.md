# Invita Studio

**A working, image-first Flutter invitation editor—not a mockup or an embedded JavaScript editor.**

The app integrates a locally vendored, improved version of the open-source [flutter_canvas_editor 1.2.0](https://pub.dev/packages/flutter_canvas_editor/versions/1.2.0) engine (BSD-3-Clause). The surrounding invitation workflow, original artwork, export services and responsive Flutter interface are implemented in this project.

## What works now

- **Live invitation details:** names, date, time, venue, address, RSVP, opening line and invitation message update the real canvas. Canvas text edits and undo/redo update the form, too.
- **Three original templates:** Botanical vows, After dark and Rosewater. Switching templates preserves words and custom text; it replaces the linked fields’ arrangement and styling and can be undone.
- **Three formats:** Classic 1080 × 1512, Story 1080 × 1920, Square 1080 × 1080. Format changes reflow linked fields and retain custom text.
- **Real canvas editing:** select, drag, resize, rotate, inline edit, add/delete custom text, arrange layers, center/straighten, change font, size, color, weight and alignment.
- **Undo/redo:** including atomic template/format changes and coalesced font-size slider changes. History is session-local, not serialized in project files.
- **High-resolution PNG and real JPEG:** 1× or 2×; up to **2160 × 3840** for Story. Export uses a frozen document snapshot, not a screenshot of the screen. Editing handles and viewport zoom are excluded.
- **Local drafts and portable projects:** debounced autosave, multiple drafts (up to 12), rename, import/export versioned editable JSON, and strict import validation.
- **Save/share plumbing:** browser Blob downloads; app-documents saving and `share_plus` native file sharing with an iPad share anchor. Native device behavior still needs validation.
- **Bundled fonts:** Cormorant Garamond, DM Sans and Noto Naskh Arabic. Basic first-strong direction detection and an Arabic-script fallback are included. No runtime font CDN.
- **Responsive UI:** desktop workspace, tablet layout and mobile editing sheets. No account, API key or backend is required.

**Status:** functional image-editor implementation with a tested Flutter web release. Android/iOS source projects and native integrations are included, but no Android/iOS binary, physical-device sharing test or store-ready release is claimed. Animated MP4 is deliberately not implemented in this increment.

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
5. Choose **Export → Create PNG/JPEG → Download/Save or Share**. Preparing the file before the final action preserves a fresh browser user gesture. Out-of-document text is flagged before image export.
6. Use **Project options → Export editable project** for a backup. Import with **Open project JSON**. A flattened PNG/JPEG is not an editable project.

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

# Start the compiled web server first, then run real-browser checks:
npm ci --prefix tool/browser
npx --prefix tool/browser playwright install --with-deps chromium
node tool/browser/smoke.cjs
node tool/browser/photo.cjs
```

**Recorded result:** analyzer clean; **64 Flutter tests passed**; **12 browser workflow checks passed**; **7 photo-card browser checks passed**. Actual downloaded PNG/JPEG signatures and dimensions were independently decoded and checked. The browser tests include live editing, photo import/styling/export, reflow, JSON backup/import, reload persistence, mobile editing/export, sharing-unavailable handling and operation without external network dependencies. See [QA results](docs/QA.md), [architecture](docs/ARCHITECTURE.md), and `docs/qa/` for evidence.

## Important boundaries

- This increment edits text and your own photos over bundled artwork. Photos are downscaled (≤1600 px), re-encoded as bounded data URLs and embedded in the project; filters, freehand drawing, QR generation, cloud sync, hosted RSVP collection, PDF/CMYK/bleed workflows and MP4 export are **not implemented**.
- RSVP and location are display text, not a backend or response-collection service.
- Browser sharing requires browser/OS support and a permitted secure context. If unavailable, the UI directs the user to download. Native sharing is wired, not device-certified.
- Drafts use local preferences/browser storage, **not encrypted cloud storage**. Clearing app/browser data, storage eviction, private-mode restrictions, quota limits or abrupt closure can lose drafts, including very recent debounced edits. Export JSON backups for important work.
- Project import permits only bundled assets, embedded photos this app created, approved fonts, supported formats, bounded transforms/text and at most 50 total nodes (including ≤8 photos, each ≤4 MB). Arbitrary URLs, filesystem paths and custom node types are rejected; project files cap at 12 MB.
- Basic Arabic-script direction/fallback is not a full multilingual typography or accessibility certification. Validate your final wording and fonts on target devices.

## Open-source provenance

App code and original artwork: **MIT**, except third-party components. The vendored engine and its local modifications remain **BSD-3-Clause**; the fonts retain **SIL OFL 1.1**. Full notices and upstream provenance are retained. No unlicensed invitation-app code, proprietary editor, FFmpeg binary or GPL video dependency was copied in.

See [third-party notices](THIRD_PARTY_NOTICES.md), `packages/flutter_canvas_editor/UPSTREAM.md`, its original `LICENSE`, the exact local `tool/vendor_patch.diff`, and `assets/fonts/*-OFL.txt`. Original artwork is reproducibly generated by `tool/generate_art.py` (optional Pillow dependency); it is already bundled.

## Next increment

After Android/iOS export/share device checks, consider photo filters/cropping, an animation scene model and a native MP4 proof of concept. Keep the editable document separate from rendered images/video. The previous research bundle remains separate from this implemented source project.
