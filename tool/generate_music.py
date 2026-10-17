"""Short original background tunes, one per celebration category.

A tiny additive synthesiser: a soft chord pad plus a plucked arpeggio over a
four-chord progression, with gentle fades so the track loops cleanly. No
external samples or libraries beyond numpy.

Output: assets/music/tune_<category>.wav (16 kHz mono, 16-bit PCM).
"""
from pathlib import Path

import numpy as np
import wave

SR = 16000
OUT = Path(__file__).resolve().parents[1] / 'assets' / 'music'
OUT.mkdir(parents=True, exist_ok=True)

# category -> (progression of triads in MIDI note numbers, bpm, octave shift)
TRACKS = {
    'wedding': ([[60, 64, 67], [55, 59, 62], [57, 60, 64], [53, 57, 60]], 72, 0),
    'engagement': ([[53, 57, 60], [60, 64, 67], [62, 65, 69], [58, 62, 65]], 80, 0),
    'birthday': ([[60, 64, 67], [65, 69, 72], [67, 71, 74], [60, 64, 67]], 116, 0),
    'anniversary': ([[57, 60, 64], [53, 57, 60], [60, 64, 67], [55, 59, 62]], 66, -12),
    'babyShower': ([[60, 64, 67], [67, 71, 74], [65, 69, 72], [60, 64, 67]], 92, 12),
    'other': ([[62, 66, 69], [57, 61, 64], [59, 62, 66], [55, 59, 62]], 88, 0),
}


def freq(note):
    return 440.0 * (2.0 ** ((note - 69) / 12.0))


def place(buffer, start, signal):
    end = min(len(buffer), start + len(signal))
    if end <= start:
        return
    buffer[start:end] += signal[: end - start]


def pluck(note, seconds, amp=0.22):
    """Plucked tone: a couple of harmonics under a fast-decay envelope."""
    n = int(SR * seconds)
    t = np.arange(n) / SR
    f = freq(note)
    env = np.exp(-4.5 * t) * (1 - np.exp(-90 * t))
    body = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * 2 * f * t)
    return amp * env * body


def pad(chord, seconds, amp=0.10):
    """Slow-swelling chord: sine voices with a rounded envelope."""
    n = int(SR * seconds)
    t = np.arange(n) / SR
    env = np.minimum(1.0, t / 0.4) * np.minimum(1.0, (seconds - t) / 0.6)
    env = np.clip(env, 0, 1)
    out = np.zeros(n)
    for note in chord:
        f = freq(note)
        out += np.sin(2 * np.pi * f * t) + 0.18 * np.sin(2 * np.pi * 2 * f * t)
    return amp * env * out / len(chord)


def render(category):
    chords, bpm, shift = TRACKS[category]
    beat = 60.0 / bpm
    loop_seconds = 4 * beat
    total = int(SR * (loop_seconds * 2 + 1.2))
    buffer = np.zeros(total)

    for repeat in range(2):
        base = int(SR * (repeat * loop_seconds))
        for index, chord in enumerate(chords):
            chord_start = base + int(index * beat * SR)
            notes = [n + shift for n in chord]
            place(buffer, chord_start, pad(notes, beat * 2.4))
            # Two arpeggio notes per beat, one octave up.
            place(buffer, chord_start, pluck(notes[0] + 12, beat * 0.9))
            place(buffer, chord_start + int(beat * 0.5 * SR), pluck(notes[1] + 12, beat * 0.9))
            place(buffer, chord_start + int(beat * 1.0 * SR), pluck(notes[2] + 12, beat * 0.9))
            place(buffer, chord_start + int(beat * 1.5 * SR), pluck(notes[1] + 12, beat * 0.9))

    # Fades, then a light smoothing pass to soften the edges.
    fade_in = int(SR * 0.5)
    fade_out = int(SR * 1.4)
    buffer[:fade_in] *= np.linspace(0, 1, fade_in)
    buffer[-fade_out:] *= np.linspace(1, 0, fade_out)
    kernel = np.ones(24) / 24
    buffer = np.convolve(buffer, kernel, mode='same')

    peak = np.max(np.abs(buffer)) or 1.0
    buffer = buffer / peak * 0.72
    return (buffer * 32767).astype('<i2')


DURATIONS_DART = (
    Path(__file__).resolve().parents[1]
    / 'lib'
    / 'domain'
    / 'category_music_durations.g.dart'
)


def wav_duration_ms(path):
    """Length of the rendered file, measured from its own header.

    The declared duration must come from the file rather than from the
    synthesiser's intent: trim bounds, fades and validation all use it, and a
    number that disagrees with the asset is silently wrong in the UI.
    """
    with wave.open(str(path), 'rb') as handle:
        frames = handle.getnframes()
        rate = handle.getframerate()
    return frames * 1000 // rate


def write_durations(durations):
    """Emits the per-category duration map the Dart code reads.

    Regenerating the tunes rewrites this file, so the two can never drift.
    """
    rows = '\n'.join(
        f"  '{category}': {ms}," for category, ms in durations.items()
    )
    DURATIONS_DART.write_text(
        '// GENERATED FILE — do not edit by hand.\n'
        '//\n'
        '// Written by `python tool/generate_music.py` from the headers of the\n'
        '// bundled WAVs in assets/music/. Regenerate the tunes to update it;\n'
        '// test/category_music_test.dart fails if this map and the assets\n'
        '// disagree.\n'
        '\n'
        '/// Bundled tune length per category (wire name), in milliseconds.\n'
        'const Map<String, int> categoryTuneDurationsMs = <String, int>{\n'
        f'{rows}\n'
        '};\n',
        encoding='utf-8',
    )
    print(f'wrote {DURATIONS_DART.relative_to(DURATIONS_DART.parents[3])}')


def main():
    durations = {}
    for category in TRACKS:
        samples = render(category)
        path = OUT / f'tune_{category}.wav'
        with wave.open(str(path), 'wb') as handle:
            handle.setnchannels(1)
            handle.setsampwidth(2)
            handle.setframerate(SR)
            handle.writeframes(samples.tobytes())
        durations[category] = wav_duration_ms(path)
        print(
            path.name,
            path.stat().st_size // 1024,
            'KB',
            f'{durations[category] / 1000:.2f} s',
        )
    write_durations(durations)


if __name__ == '__main__':
    main()
