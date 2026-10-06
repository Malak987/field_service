import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// A real (tiny, valid) 1x1 PNG — enough for `Image.memory` / `Image.file`
/// to decode in widget tests and for byte-level assertions in sync tests.
final Uint8List kTestPhotoBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

/// Writes [kTestPhotoBytes] into [directory] as a stand-in for a file the
/// camera/gallery just produced, and returns it.
///
/// Synchronous on purpose: widget-test bodies run inside `FakeAsync`, where
/// awaiting dart:io futures never completes. Sync I/O is safe there.
File writeTempPhoto(Directory directory, String name) {
  final File file = File(p.join(directory.path, name));
  file.writeAsBytesSync(kTestPhotoBytes);
  return file;
}
