import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as img;

/// A photo the host can place on the canvas, stored as a portable data URL.
class PreparedPhoto {
  const PreparedPhoto({
    required this.dataUrl,
    required this.width,
    required this.height,
  });

  /// `data:image/jpeg;base64,…` — safe to persist inside a project.
  final String dataUrl;
  final int width, height;

  double get aspectRatio => width / height;
}

/// Browsable image types accepted by [pickPhotoBytes].
const photoTypeGroup = XTypeGroup(
  label: 'Photo',
  extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
  mimeTypes: [
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'image/bmp',
  ],
);

/// Opens a picker and returns the chosen file's bytes, or `null` if cancelled.
Future<Uint8List?> pickPhotoBytes() async {
  final file = await openFile(acceptedTypeGroups: const [photoTypeGroup]);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (bytes.lengthInBytes > _maxInputBytes) {
    throw const FormatException('That photo is larger than 25 MB.');
  }
  return bytes;
}

/// A photo is bounded so drafts, exports and projects stay portable.
const int maxPhotoDataUrlBytes = 4 * 1024 * 1024;
const int _maxInputBytes = 25 * 1024 * 1024;
const int _maxDimension = 1600;

const Set<String> _allowedPhotoDataUrlHeaders = {
  'data:image/png;base64,',
  'data:image/jpeg;base64,',
  'data:image/webp;base64,',
  'data:image/gif;base64,',
  'data:image/bmp;base64,',
};

String? _photoDataUrlHeader(String? assetId) {
  if (assetId == null || assetId.length > maxPhotoDataUrlBytes) return null;
  for (final header in _allowedPhotoDataUrlHeaders) {
    if (assetId.startsWith(header)) return header;
  }
  return null;
}

/// Returns the decoded bytes of a host-owned image data URL, or `null` when
/// [assetId] is not one this app produced.
Uint8List? photoBytesFromDataUrl(String? assetId) {
  final header = _photoDataUrlHeader(assetId);
  if (header == null) return null;
  try {
    return base64Decode(assetId!.substring(header.length));
  } catch (_) {
    return null;
  }
}

/// Whether [assetId] is an embedded photo this app is willing to load.
bool isPhotoDataUrl(String? assetId) => _photoDataUrlHeader(assetId) != null;

/// A bounded memo of decoded photo bytes keyed by the full data URL.
///
/// Thumbnails re-base64-decode megabytes on every widget rebuild otherwise;
/// [photoBytesCached] keeps the last few around instead.
final Map<String, Uint8List> _photoBytesCache = {};
const int _photoBytesCacheLimit = 8;

Uint8List? photoBytesCached(String? assetId) {
  if (assetId == null || assetId.length > maxPhotoDataUrlBytes) return null;
  final hit = _photoBytesCache[assetId];
  if (hit != null) return hit;
  final bytes = photoBytesFromDataUrl(assetId);
  if (bytes == null) return null;
  _photoBytesCache[assetId] = bytes;
  while (_photoBytesCache.length > _photoBytesCacheLimit) {
    _photoBytesCache.remove(_photoBytesCache.keys.first);
  }
  return bytes;
}

/// Photos above this size decode/resize/encode on a background isolate;
/// smaller ones finish faster on the UI thread than the isolate round-trip.
const int photoIsolateMinBytes = 256 * 1024;

/// Decodes any supported image, downscales it and re-encodes it as a JPEG
/// data URL. Throws [FormatException] when the file is not a usable image.
/// Heavy for large inputs — callers with big byte arrays should run it via
/// `compute` (see [photoIsolateMinBytes]).
PreparedPhoto preparePhoto(Uint8List input) {
  if (input.isEmpty) {
    throw const FormatException('That photo is empty.');
  }
  var decoded = img.decodeImage(input);
  if (decoded == null) {
    throw const FormatException(
      'That file is not a supported photo. Use a JPEG, PNG or WebP image.',
    );
  }
  decoded = img.bakeOrientation(decoded);
  if (decoded.width > _maxDimension || decoded.height > _maxDimension) {
    final landscape = decoded.width >= decoded.height;
    decoded = img.copyResize(
      decoded,
      width: landscape ? _maxDimension : null,
      height: landscape ? null : _maxDimension,
      interpolation: img.Interpolation.average,
    );
  }
  final jpeg = img.encodeJpg(decoded, quality: 82);
  final dataUrl = 'data:image/jpeg;base64,${base64Encode(jpeg)}';
  if (dataUrl.length > maxPhotoDataUrlBytes) {
    throw const FormatException(
      'That photo is too detailed to store. Try a smaller image.',
    );
  }
  return PreparedPhoto(
    dataUrl: dataUrl,
    width: decoded.width,
    height: decoded.height,
  );
}
