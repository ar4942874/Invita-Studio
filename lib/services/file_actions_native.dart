import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

Future<String?> saveBytes(Uint8List bytes, String name, String mime) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final documents = await getApplicationDocumentsDirectory();
    final folder = Directory('${documents.path}/InvitaStudioExports');
    await folder.create(recursive: true);
    final file = File('${folder.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return 'Saved inside this app: ${file.path}. Use Share to save to Files, Photos, or another app.';
  }
  final location = await getSaveLocation(suggestedName: name);
  if (location == null) return null;
  await XFile.fromData(bytes, mimeType: mime, name: name).saveTo(location.path);
  return 'Saved to ${location.path}';
}
