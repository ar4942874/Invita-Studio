import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:invitation_studio/domain/category_music.dart';
import 'package:invitation_studio/domain/category_music_durations.g.dart';
import 'package:invitation_studio/domain/invitation_template.dart';

/// The parts of a WAV header this test needs, read from the file itself.
class _Wav {
  const _Wav({
    required this.channels,
    required this.sampleRate,
    required this.bits,
    required this.frames,
  });

  final int channels;
  final int sampleRate;
  final int bits;
  final int frames;

  /// Playback length, floored exactly like the generator does.
  int get durationMs => frames * 1000 ~/ sampleRate;
}

/// Minimal RIFF/WAVE reader.
///
/// The test deliberately parses the bytes instead of trusting the generated
/// map: a map that agrees with itself proves nothing.
_Wav _readWav(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  String tag(int offset) =>
      String.fromCharCodes(bytes.sublist(offset, offset + 4));
  expect(tag(0), 'RIFF', reason: '$path is not a RIFF file');
  expect(tag(8), 'WAVE', reason: '$path is not a WAVE file');

  int? channels, sampleRate, bits, dataSize;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = tag(offset);
    final size = data.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ') {
      channels = data.getUint16(body + 2, Endian.little);
      sampleRate = data.getUint32(body + 4, Endian.little);
      bits = data.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      dataSize = size;
      break;
    }
    // Chunks are word aligned.
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  final channelCount = channels;
  final sampleWidth = bits;
  final sampleCount = dataSize;
  final rate = sampleRate;
  if (channelCount == null || sampleWidth == null || sampleCount == null || rate == null) {
    fail('$path is missing a readable fmt or data chunk');
  }
  final blockAlign = channelCount * (sampleWidth ~/ 8);
  return _Wav(
    channels: channelCount,
    sampleRate: rate,
    bits: sampleWidth,
    frames: sampleCount ~/ blockAlign,
  );
}

void main() {
  group('bundled tune metadata matches the bundled audio', () {
    test('every declared duration equals the length in the WAV header', () {
      for (final category in InvitationCategory.values) {
        final path = CategoryMusic.assetPath(category);
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path is missing');
        final wav = _readWav(path);
        expect(
          CategoryMusic.durationFor(category),
          wav.durationMs,
          reason:
              '${category.wireName}: declared '
              '${CategoryMusic.durationFor(category)} ms but the file is '
              '${wav.durationMs} ms — regenerate with '
              '`python tool/generate_music.py`',
        );
      }
    });

    test('the generated map has one entry per category and no strays', () {
      expect(
        categoryTuneDurationsMs.keys.toSet(),
        {for (final c in InvitationCategory.values) c.wireName},
      );
      for (final entry in categoryTuneDurationsMs.entries) {
        expect(
          entry.value,
          inInclusiveRange(4000, 30000),
          reason: '${entry.key} is not a plausible short tune',
        );
      }
    });

    test('the tunes are the documented 16 kHz mono 16-bit format', () {
      for (final category in InvitationCategory.values) {
        final wav = _readWav(CategoryMusic.assetPath(category));
        expect(wav.sampleRate, 16000, reason: category.wireName);
        expect(wav.channels, 1, reason: category.wireName);
        expect(wav.bits, 16, reason: category.wireName);
      }
    });

    test('a new project records the real length, not the old guess', () {
      for (final category in InvitationCategory.values) {
        final audio = CategoryMusic.forCategory(category);
        expect(audio.durationMs, CategoryMusic.durationFor(category));
        expect(
          audio.durationMs,
          isNot(12000),
          reason: '${category.wireName} still uses the old fixed guess',
        );
      }
    });

    test('asset IDs resolve to the same length as their category', () {
      for (final category in InvitationCategory.values) {
        final id = CategoryMusic.tuneId(category);
        expect(CategoryMusic.isTune(id), isTrue);
        expect(
          CategoryMusic.durationForAsset(id),
          CategoryMusic.durationFor(category),
        );
      }
      // Unknown IDs fall back to the shortest real tune rather than to zero,
      // so a trim slider can never be built with a zero maximum.
      expect(
        CategoryMusic.durationForAsset('tune_unknown'),
        CategoryMusic.fallbackDurationMs,
      );
      expect(
        CategoryMusic.fallbackDurationMs,
        categoryTuneDurationsMs.values.reduce((a, b) => a < b ? a : b),
      );
    });
  });
}
