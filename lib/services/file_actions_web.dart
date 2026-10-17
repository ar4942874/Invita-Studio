import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// `window.showSaveFilePicker` (File System Access API). It is not exposed by
/// `package:web`, so it is declared here. Null/undefined when unsupported.
@JS('showSaveFilePicker')
external JSFunction? get _showSaveFilePicker;

bool get _isEmbedded => web.window.top != web.window.self;

bool get _isMobile {
  final navigator = web.window.navigator;
  final userAgent = navigator.userAgent;
  if (RegExp(
    r'Android|iPhone|iPad|iPod|Mobile',
    caseSensitive: false,
  ).hasMatch(userAgent)) {
    return true;
  }
  // iPadOS reports as Macintosh but exposes more than one touch point.
  return userAgent.contains('Macintosh') && navigator.maxTouchPoints > 1;
}

Future<String?> saveBytes(Uint8List bytes, String name, String mime) async {
  final picker = _showSaveFilePicker;
  // Desktop Chrome/Edge get a real "Save as" dialog, which is the most reliable
  // path. Skipped when embedded (the picker is not permitted and can stall) or
  // under browser automation, where it never resolves.
  if (picker != null && !_isEmbedded && !web.window.navigator.webdriver) {
    try {
      final options = {'suggestedName': name}.jsify()!;
      final promise =
          picker.callAsFunction(web.window, options)
              as JSPromise<web.FileSystemFileHandle>;
      final handle = await promise.toDart;
      final stream = await handle.createWritable().toDart;
      await stream.write(bytes.toJS).toDart;
      await stream.close().toDart;
      return 'Saved $name';
    } catch (error) {
      if (error.toString().contains('AbortError')) return 'Save cancelled.';
      // The picker can be blocked (sandboxed frame, permissions): fall through.
    }
  }

  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  Timer(const Duration(seconds: 60), () => web.URL.revokeObjectURL(url));

  // Sandboxed preview iframes and mobile browsers commonly ignore the
  // `<a download>` click. Opening the file in a new tab still lets the user
  // save it.
  if ((_isEmbedded || _isMobile) && web.window.open(url, '_blank') != null) {
    return 'Opened $name in a new tab. Save it from there.';
  }

  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body!.appendChild(link);
  link.click();
  link.remove();
  return 'Download started: $name';
}
