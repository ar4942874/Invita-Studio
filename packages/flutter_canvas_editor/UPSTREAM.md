# Vendored engine: upstream and local changes

- Package: **flutter_canvas_editor 1.2.0** (not the differently named `canvas_editor` package).
- Upstream: https://github.com/developer-estatic/canvas_editor
- Published source: https://pub.dev/api/archives/flutter_canvas_editor-1.2.0.tar.gz
- Archive SHA-256, verified against pub.dev metadata: `f26be63f9e044564ce440588e28d7165edb3c50f572e81a895826c0495ce90d6`.
- License: **BSD-3-Clause**, copyright (c) 2026 Estatic Infotech Pvt. Ltd. The original `LICENSE`, README, examples and tests are retained.
- These local changes are also distributed under BSD-3-Clause. This is a project-local fork, not an upstream release or a claim of upstream endorsement.

## Invitation-specific improvements

1. Added awaitable `applyDocument`: host field/template/format updates become one atomic, undoable document change instead of resetting history or racing queued node updates.
2. PNG export freezes the document before awaiting images, validates positive/finite sizes and scale, caps output at 16,777,216 pixels, fails on missing image assets, and cleans up picture/image handles in `finally`.
3. Image loading clones provider image handles before transferring ownership, disposes received `ImageInfo` and local codecs, disposes late asynchronous results after widget teardown, and prunes unused live-canvas images.
4. Live painting snapshots its image-cache map and repaints when decoded images arrive. Downscaled artwork uses filtered image rendering.
5. Text alignment uses the full frame width, fixing single-line center/right alignment in the painter and exported PNG.
6. Added configurable `viewportPadding` with upstream-compatible default 20. The invitation host requests 0 inside its own paper frame.
7. Selection pictures and text-measurement/paint resources are disposed.
8. Inline text commits when focus leaves; inline input is limited to 500 characters. Basic first-strong Arabic-script direction detection and a host-registered `NotoNaskhArabic` fallback are used in measurement, live editing and painting.
9. First-drag selection can move the hit layer; dragging another layer no longer moves the old selection, and dragging empty paper does not move an unrelated layer. Drag origin is pointer-down; cancelled gestures commit the partial change.
10. Minor formatting/lint fixes, including two unused callback-parameter names in an upstream test.

`../../tool/vendor_patch.diff` records the exact Dart diff against the verified published archive. `UPSTREAM.json` records the changed paths and source digest. The patch is **already applied**; do not apply it again to this copy. To upgrade, compare a fresh upstream archive and re-review/retest the changes rather than blindly replacing the package.

The host uses only built-in background and text nodes. Upstream custom-widget nodes are not rendered into PNG and are not accepted by this app’s project importer. The fork is a young dependency; retain the app’s export/history/interaction regression tests when updating it.
