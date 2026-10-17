# Sample video files

These files exist so the export format can be inspected without an Android or
iOS device. **They were not produced by the Flutter app.** The sandbox used to
prepare this branch has no Flutter/Dart SDK, Android SDK, JDK or Xcode, so the
app could not be built or run here. See [the verification report](../VIDEO.md)
for exactly what was and was not executed.

| File | What it is |
|---|---|
| `sample-invitation-music.mp4` | 15 s, 1080 × 1920, 30 fps H.264 High/yuv420p + AAC-LC stereo, rendered by `tool/reference_sample.py` with the app's bundled artwork, fonts, layout constants and entrance timings. |
| `sample-invitation-silent.mp4` | Same render without an audio track, to show the "silent MP4" case. |
| `storyboard.jpg` | Six frames from the music sample at 0.2 s, 0.8 s, 2.4 s, 5.5 s, 9.0 s and 14.6 s — the fade/slide/zoom entrances and the closing exit. |

## Why a reference render exists

The Dart export pipeline paints frames with the same `TimelineFrameRenderer`
used by the live preview, then hands raw RGBA to the platform H.264 encoder
(`MediaCodec` on Android, `AVAssetWriter` on iOS). None of that can execute in a
Linux sandbox without those SDKs. The Python tool reproduces the same document
geometry, fonts, colours and `evaluateTimeline` maths so the container, codec,
duration, frame count, colour tags and audio layout can be checked with an
independent decoder (ffmpeg 7.0.2, via `imageio-ffmpeg`).

It is a verification aid only; it is not shipped in the app and the app does not
call it.

## Regenerating

```sh
python3 -m pip install --break-system-packages pillow imageio-ffmpeg
FFMPEG=$(python3 -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())")

python3 tool/reference_sample.py \
  --out docs/samples/sample-invitation-silent.mp4 --ffmpeg "$FFMPEG"

python3 tool/reference_sample.py \
  --out docs/samples/sample-invitation-music.mp4 \
  --music /tmp/reference-music.wav --ffmpeg "$FFMPEG"
```

`reference_sample.py` synthesises a soft four-note ambient bed for the music
sample; no third-party recording is redistributed.

## Measured properties (ffmpeg 7.0.2)

| Property | `sample-invitation-music.mp4` | `sample-invitation-silent.mp4` |
|---|---|---|
| Container | MP4 (`isom`), `moov` before `mdat` (fast start) | same |
| Video | H.264 High, yuv420p, bt709, 1080 × 1920, 30 fps | same |
| Decoded video frames | 450 | 450 |
| Duration | 15.00 s | 15.00 s |
| Audio | AAC-LC, 44.1 kHz stereo, ~127 kb/s | none |
| Size | 671,145 bytes | 420,223 bytes |

`ffmpeg` (not `ffprobe`) was used for inspection; `ffprobe` is not installed in
the sandbox and is not a dependency of the app.

The app's own native encoders are configured for **Baseline** H.264 (Android
prefers an encoder that advertises Baseline; iOS sets
`AVVideoProfileLevelH264BaselineAutoLevel`) and 8 Mb/s at 1080 × 1920, so real
device output will be larger than this CRF-based reference render.
