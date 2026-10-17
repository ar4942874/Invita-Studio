#!/usr/bin/env python3
"""Render the reference sample MP4 used in the verification report.

This is a development tool, not part of the Flutter app. It reproduces the
Botanical Story layout (same artwork, fonts, positions, colours) and the same
entrance timings the app's timeline model evaluates, then encodes with ffmpeg.

The app itself renders frames with Flutter's canvas and encodes them with the
platform H.264 encoder. The sandbox used to build this repository has no
Flutter/Dart SDK and no Android/iOS toolchain, so this reference render exists
only to provide a playable artefact and to prove the container/mime/format
decisions. It is NOT produced by the app.

Usage:
  python3 tool/reference_sample.py --out docs/samples/sample-invitation-music.mp4 \
      --music docs/samples/reference-music.wav
  python3 tool/reference_sample.py --out docs/samples/sample-invitation-silent.mp4
"""

from __future__ import annotations

import argparse
import math
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
W, H = 1080, 1920
FPS = 30
DURATION_MS = 15000
FRAMES = DURATION_MS * FPS // 1000

INK = (53, 74, 61, 255)
ACCENT = (122, 119, 92, 255)
PAPER = (246, 243, 235, 255)

CORMORANT = ROOT / "assets/fonts/CormorantGaramond.ttf"
DMSANS = ROOT / "assets/fonts/DMSans.ttf"


class Layer:
    def __init__(self, text, y, size, font, color, align="center", spacing=0.0):
        self.text = text
        self.y = y
        self.size = size
        self.font_path = font
        self.color = color
        self.align = align
        self.spacing = spacing
        self._font = ImageFont.truetype(str(font), size)


def ease_out(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return 1 - (1 - t) * (1 - t)


def build_layers():
    """Text and positions mirror InvitationTemplate.createDocument(story)."""
    h = H
    return {
        "header": Layer("TOGETHER WITH THEIR FAMILIES", .202 * h, 22, DMSANS, INK, spacing=3.2),
        "first": Layer("Ayesha", .268 * h, 164, CORMORANT, INK),
        "amp": Layer("&", .382 * h, 68, CORMORANT, ACCENT),
        "second": Layer("Hamza", .435 * h, 164, CORMORANT, INK),
        "message": Layer(
            "joyfully invite you to celebrate\ntheir wedding",
            .567 * h, 29, CORMORANT, INK,
        ),
        "date": Layer("SATURDAY, 12 DECEMBER 2026", .650 * h, 30, DMSANS, INK, spacing=2.2),
        "time": Layer("Reception at 7:00 in the evening", .696 * h, 26, DMSANS, INK),
        "venue": Layer("The Royal Orchard", .757 * h, 42, CORMORANT, INK),
        "address": Layer("Bahawalpur, Punjab", .805 * h, 24, DMSANS, INK),
        "rsvp": Layer(
            "Kindly RSVP by 01 December\n+92 300 123 4567",
            .881 * h, 23, DMSANS, ACCENT,
        ),
    }


# (start, end) entrance window, effect, delay
ENTRANCES = {
    "header": (0, 800, "fade", 0),
    "first": (200, 1200, "slideUp", 0),
    "amp": (900, 1700, "zoomIn", 0),
    "second": (1400, 2400, "slideUp", 0),
    "message": (2000, 3000, "fade", 0),
    "date": (2600, 3400, "fade", 0),
    "time": (2900, 3700, "fade", 0),
    "venue": (3300, 4100, "slideUp", 0),
    "address": (3800, 4600, "fade", 0),
    "rsvp": (4500, 5300, "fade", 0),
}
EXIT_START_MS = 14200
EXIT_END_MS = 15000


def layer_state(name: str, t_ms: float):
    """Returns (opacity, dy, scale) using the app's evaluation rules."""
    if t_ms >= EXIT_END_MS:
        return 0.0, 0.0, 1.0
    opacity, dy, scale = 1.0, 0.0, 1.0
    start, end, effect, delay = ENTRANCES[name]
    if t_ms < end:
        p = max(0.0, min(1.0, (t_ms - start - delay) / max(1, (end - start))))
        p = ease_out(p)
        if effect == "fade":
            opacity = p
        elif effect == "slideUp":
            opacity = p
            dy = (1 - p) * 96
        elif effect == "zoomIn":
            opacity = p
            scale = 0.9 + 0.1 * p
    if t_ms >= EXIT_START_MS:
        q = ease_out((t_ms - EXIT_START_MS) / (EXIT_END_MS - EXIT_START_MS))
        opacity *= 1 - q
    return opacity, dy, scale


def draw_text_layer(layer: Layer, opacity: float, dy: float, scale: float) -> Image.Image:
    """Draw one layer with the same fade/slide/zoom semantics as the app."""
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    if opacity <= 0.002:
        return canvas
    size = max(1, int(layer.size * scale))
    line_height = size * 1.15
    lines = layer.text.split("\n")
    total = line_height * len(lines)
    center_y = layer.y + layer.size * 1.15 * len(lines) / 2 + dy
    top = center_y - total / 2
    text = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(text)
    font = ImageFont.truetype(str(layer.font_path), size)
    for index, line in enumerate(lines):
        baseline = top + index * line_height + line_height / 2
        if layer.spacing > 0:
            _draw_spaced(draw, line, layer, baseline, font, spacing=layer.spacing * scale)
        else:
            draw.text((W / 2, baseline), line, font=font, fill=layer.color, anchor="mm")
    alpha = text.getchannel("A").point(lambda a: int(a * opacity))
    text.putalpha(alpha)
    canvas.alpha_composite(text)
    return canvas


def _draw_spaced(draw, line, layer: Layer, center_y: float, font, spacing: float) -> None:
    widths = [draw.textbbox((0, 0), ch, font=font)[2] for ch in line]
    total = sum(widths) + spacing * max(0, len(line) - 1)
    x = W / 2 - total / 2
    for ch, width in zip(line, widths):
        draw.text((x, center_y), ch, font=font, fill=layer.color, anchor="lm")
        x += width + spacing


def background(t_ms: float) -> Image.Image:
    art = Image.open(ROOT / "assets/art/botanical_story.png").convert("RGB")
    art = art.resize((W, H))
    zoom = 1.0 + 0.04 * (t_ms / DURATION_MS)
    crop_w, crop_h = W / zoom, H / zoom
    left = (W - crop_w) / 2
    top = (H - crop_h) / 2
    cropped = art.crop((int(left), int(top), int(left + crop_w), int(top + crop_h)))
    return cropped.resize((W, H), Image.LANCZOS)


def synth_music(path: Path, duration_ms: int) -> None:
    rate = 44100
    seconds = duration_ms / 1000
    frames = int(rate * seconds)
    notes = [220.0, 277.18, 329.63, 440.0]
    with wave_open(path) as wav:
        for i in range(frames):
            t = i / rate
            env = min(1.0, t / 2.5) * min(1.0, max(0.0, (seconds - t) / 2.0))
            value = 0.0
            for index, freq in enumerate(notes):
                value += math.sin(2 * math.pi * freq * t + index) * 0.11
            value *= env * 0.5
            sample = int(max(-1.0, min(1.0, value)) * 32767)
            wav.writeframes(struct.pack("<hh", sample, sample))


class wave_open:
    import wave as _wave

    def __init__(self, path: Path):
        self.path = path

    def __enter__(self):
        import wave

        self._wav = wave.open(str(self.path), "wb")
        self._wav.setnchannels(2)
        self._wav.setsampwidth(2)
        self._wav.setframerate(44100)
        return self._wav

    def __exit__(self, *exc):
        self._wav.close()
        return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--music", default="")
    parser.add_argument("--ffmpeg", required=True)
    parser.add_argument("--frames", type=int, default=FRAMES)
    args = parser.parse_args()

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    layers = build_layers()

    music_path = args.music
    if music_path:
        music = Path(music_path)
        music.parent.mkdir(parents=True, exist_ok=True)
        synth_music(music, DURATION_MS)

    cmd = [
        args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
    ]
    if music_path:
        cmd += ["-i", music_path]
    cmd += [
        "-c:v", "libx264", "-preset", "medium", "-crf", "20",
        "-profile:v", "high", "-level", "4.1", "-pix_fmt", "yuv420p",
        "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
        "-movflags", "+faststart",
    ]
    if music_path:
        cmd += ["-c:a", "aac", "-b:a", "128k", "-shortest"]
    else:
        cmd += ["-an"]
    cmd += [str(out)]

    process = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    assert process.stdin is not None
    for frame_index in range(args.frames):
        t_ms = frame_index * 1000 / FPS
        image = background(t_ms).convert("RGBA")
        for name, layer in layers.items():
            opacity, dy, scale = layer_state(name, t_ms)
            image.alpha_composite(draw_text_layer(layer, opacity, dy, scale))
        process.stdin.write(image.convert("RGB").tobytes())
        if frame_index % 60 == 0:
            print(f"frame {frame_index}/{args.frames}", file=sys.stderr)
    process.stdin.close()
    code = process.wait()
    print(f"wrote {out} ({out.stat().st_size if out.exists() else 0} bytes)")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
