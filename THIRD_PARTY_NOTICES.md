# Third-party notices

The app code and original invitation artwork are MIT-licensed except as noted below. Third-party code/fonts retain their original licenses. Preserve these notices and the underlying license texts when redistributing. This is a project-local integration, not an upstream endorsement.

## Editor foundation

**flutter_canvas_editor 1.2.0** — BSD-3-Clause, Estatic Infotech Pvt. Ltd.

- Source: https://github.com/developer-estatic/canvas_editor
- Package: https://pub.dev/packages/flutter_canvas_editor/versions/1.2.0
- Original license: `packages/flutter_canvas_editor/LICENSE`
- Fork provenance and changes: `packages/flutter_canvas_editor/UPSTREAM.md`, `UPSTREAM.json`, `tool/vendor_patch.diff`
- The original copyright, license and disclaimer remain in the vendored package; local engine modifications are also BSD-3-Clause.

### Complete editor license

```text
BSD 3-Clause License

Copyright (c) 2026 Estatic Infotech Pvt. Ltd.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from this
   software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Bundled fonts — SIL Open Font License 1.1

These are unmodified font files, locally bundled, not a claim that a fonts wrapper licenses font artwork.

| Font | Original source directory | Complete license |
|---|---|---|
| Cormorant Garamond regular/italic | https://github.com/google/fonts/tree/main/ofl/cormorantgaramond | `assets/fonts/CormorantGaramond-OFL.txt` |
| DM Sans | https://github.com/google/fonts/tree/main/ofl/dmsans | `assets/fonts/DMSans-OFL.txt` |
| Noto Naskh Arabic | https://github.com/google/fonts/tree/main/ofl/notonaskharabic | `assets/fonts/NotoNaskhArabic-OFL.txt` |

Font licenses are also registered in Flutter’s in-app About → Licenses screen. Keep the complete OFL texts and respect reserved font-name conditions if modifying the font files.

## Resolved packages used by the implementation

| Component | Resolved version | License family |
|---|---|---|
| Flutter / Dart | Flutter 3.47.7 / Dart 3.13.5 | BSD-style; bundled third-party notices apply |
| `flutter_canvas_editor` (local fork) | 1.2.0 | BSD-3-Clause |
| `flutter_bloc` / `equatable` | 9.1.1 / 3.0.0 | MIT |
| `image` (native/VM JPEG path) | 4.12.0 | MIT |
| `share_plus` | 13.3.1 | BSD-3-Clause |
| `shared_preferences` | 2.5.6 | BSD-3-Clause |
| `file_selector` | 1.1.0 | BSD-3-Clause |
| `cross_file` | 0.3.5+5 | BSD-3-Clause |
| `path_provider` | 2.1.6 | BSD-3-Clause |
| `web` | 1.1.1 | BSD-3-Clause |
| `cupertino_icons` | 1.0.9 | MIT |

`pubspec.lock` records all resolved direct/transitive dependencies. Flutter’s generated dependency license notices are reproduced in `docs/DEPENDENCY_NOTICES.txt` and in the compiled app’s license assets. That notice file is generated, not replaced by this summary table. Build tools and transitive/native platform dependencies may carry additional notices; retain the generated notices when rebuilding/distributing.

Playwright is an optional Apache-2.0 development dependency for browser QA, not a runtime app dependency. Its installed browser/tool files are not included in the source bundle. Pillow is an optional development tool for regenerating artwork, not a runtime dependency.

## Original artwork and code

The botanical branches, celestial linework, rosewater washes, brand icon, app workflow and host UI were created for this project. The original art generator is `tool/generate_art.py`; baked assets are included. These are not scraped invitation templates or copied art from an unlicensed sample app. App code/artwork use the root MIT license; the engine fork and fonts retain their separate licenses above.

No Invitor source, stock music, proprietary editor, FFmpeg binary or GPL video package is included. Future photo, art, music or video additions require their own rights/license review.
