import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:field_service/core/storage/file_storage.dart';

/// [FileStorage] rooted in an application-owned directory.
///
/// Physical root: `<application documents>/files/`, resolved lazily through
/// `path_provider` (the first call may touch the platform channel). Callers
/// only ever pass **relative** paths, which the database persists — absolute
/// paths change between installs and OS upgrades and would break stored
/// references after an update.
class AppFileStorage implements FileStorage {
  AppFileStorage({this._baseDirectory});

  /// Override for tests (a temp directory); production uses the
  /// application documents directory.
  final Directory? _baseDirectory;
  Directory? _rootCache;

  Future<Directory> _root() async {
    Directory? root = _rootCache;
    if (root == null) {
      final Directory base =
          _baseDirectory ??
          Directory(
            p.join((await getApplicationDocumentsDirectory()).path, 'files'),
          );
      if (!await base.exists()) {
        await base.create(recursive: true);
      }
      root = base;
      _rootCache = base;
    }
    return root;
  }

  /// Normalises a relative path (relative to the storage root) and rejects
  /// anything that would escape it (absolute paths, `..` segments) so a bad
  /// reference can never read or write outside the app's files.
  static String normalize(String relativePath) {
    if (relativePath.isEmpty || p.isAbsolute(relativePath)) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'File paths must be relative to the storage root.',
      );
    }
    final String normalized = p.normalize(relativePath);
    if (normalized == '.' ||
        normalized.startsWith('..') ||
        p.split(normalized).contains('..')) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'File paths must stay inside the storage root.',
      );
    }
    return normalized;
  }

  @override
  Future<String> write({
    required String relativePath,
    required List<int> bytes,
  }) async {
    final String safePath = normalize(relativePath);
    final Directory root = await _root();
    final File file = File(p.join(root.path, safePath));

    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);

    return safePath;
  }

  @override
  Future<List<int>?> read(String relativePath) async {
    final String safePath = normalize(relativePath);
    final Directory root = await _root();
    final File file = File(p.join(root.path, safePath));

    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  @override
  Future<bool> exists(String relativePath) async {
    final String safePath = normalize(relativePath);
    final Directory root = await _root();
    final File file = File(p.join(root.path, safePath));

    return file.existsSync();
  }

  @override
  Future<void> delete(String relativePath) async {
    // Idempotent by contract: deleting a missing file is a no-op, so retried
    // deletes during sync never throw.
    final String safePath = normalize(relativePath);
    final Directory root = await _root();
    final File file = File(p.join(root.path, safePath));

    if (await file.exists()) {
      await file.delete();
    }
  }
}
