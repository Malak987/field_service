/// Stores binary files (before/after photos, customer signatures, documents)
/// on the device, next to the local database.
///
/// Files are addressed by a **relative** path: the implementation decides the
/// physical root (the application documents directory via `path_provider`), and
/// the database only stores the relative reference. Absolute container paths
/// change between installs and OS upgrades, so persisting one would break every
/// stored reference after an update.
///
/// Phase 3 status: **interface only — no implementation exists yet.** It is
/// declared now because the job files feature (photos and signatures) and the
/// sync engine both need to agree on the same contract, and because it keeps
/// `dart:io` and `path_provider` out of the Domain layer: a use case depends on
/// this abstraction, never on the file system.
abstract interface class FileStorage {
  /// Writes [bytes] to [relativePath], creating parent directories as needed,
  /// and returns the stored relative path.
  Future<String> write({
    required String relativePath,
    required List<int> bytes,
  });

  /// Reads [relativePath].
  ///
  /// Returns `null` when the file is gone (the OS may clear caches, or the user
  /// may delete media) so callers can decide whether to re-download it.
  Future<List<int>?> read(String relativePath);

  /// Whether [relativePath] currently exists on the device.
  Future<bool> exists(String relativePath);

  /// Deletes [relativePath].
  ///
  /// Must be a no-op when the file no longer exists, so that retried deletes
  /// during sync stay idempotent.
  Future<void> delete(String relativePath);
}
