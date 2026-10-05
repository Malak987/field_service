import 'dart:io';

import 'package:drift/drift.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:field_service/core/database/app_database.dart';
import 'package:field_service/core/database/tables/job_files_table.dart';
import 'package:field_service/core/sync/sync_operation.dart';
import 'package:field_service/core/sync/sync_queue.dart';
import 'package:field_service/core/storage/file_storage.dart';

/// Registers job files (before/after photos, customer signatures) in local
/// app-owned storage and queues their upload.
///
/// Guarantees:
/// * **Stable identity.** Every file gets a client-generated uuid at
///   registration time; that id is the same one the sync queue, the local
///   row and the future remote object all use. Retries never create a new id.
/// * **No dependence on camera/gallery temp paths.** Picked files are copied
///   into app-owned storage *immediately*; the OS may clean its temp areas at
///   any time and that must not lose a captured photo.
/// * **Delete safety.** A local file is only deleted after its upload has
///   been confirmed ([markUploaded] → [deleteAfterConfirmedUpload]);
///   [deleteAfterConfirmedUpload] refuses to run otherwise.
/// * **Offline safe.** Storing a file never touches the network; the upload
///   is a regular sync-queue operation that waits for internet like any
///   other change.
class LocalFileStorage {
  LocalFileStorage({
    required this._fileStorage,
    required this._database,
    required this._syncQueue,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final FileStorage _fileStorage;
  final AppDatabase _database;
  final SyncQueue _syncQueue;
  final DateTime Function() _now;

  static const Uuid _uuid = Uuid();

  /// Copies a picked file (camera / gallery [XFile]) into app-owned storage
  /// and registers it. Returns the stable file id.
  ///
  /// The [XFile] from `image_picker` may live in a temporary directory; only
  /// its bytes are what matter here.
  Future<String> storePickedFile({
    required XFile picked,
    required String jobId,
    required JobFileType fileType,
    String? fileName,
    DateTime? capturedAt,
    String? mimeType,
  }) {
    return storeFile(
      source: File(picked.path),
      jobId: jobId,
      fileType: fileType,
      fileName: fileName,
      capturedAt: capturedAt,
      mimeType: mimeType ?? picked.mimeType,
    );
  }

  /// Stores any local [source] file (e.g. an already-copied export) with the
  /// same guarantees as [storePickedFile].
  Future<String> storeFile({
    required File source,
    required String jobId,
    required JobFileType fileType,
    String? fileName,
    DateTime? capturedAt,
    String? mimeType,
  }) async {
    final DateTime now = _now();

    // 1) Stable identity + stable, collision-free storage path.
    final String fileId = _uuid.v4();
    final String sourceName =
        fileName ?? p.basenameWithoutExtension(source.path);
    final String extension = p.extension(source.path);
    final String relativePath = '${fileType.name}/$fileId$extension';

    // 2) Copy the bytes into app-owned storage NOW. From this point the OS
    //    is free to clean up its temporary directories.
    final List<int> bytes = await source.readAsBytes();
    await _fileStorage.write(relativePath: relativePath, bytes: bytes);

    // 3) Register the metadata locally (source of truth for the UI).
    await _database
        .into(_database.jobFilesTable)
        .insert(
          JobFilesTableCompanion.insert(
            id: fileId,
            jobId: jobId,
            localPath: relativePath,
            remotePath: const Value(null),
            fileType: fileType.name,
            fileName: sourceName,
            mimeType: Value(mimeType),
            sizeBytes: Value(bytes.length),
            capturedAt: capturedAt ?? now,
            syncStatus: const Value('pending'),
            localUpdatedAt: Value(now),
            lastSyncedAt: const Value(null),
          ),
        );

    // 4) Queue the upload. The payload carries everything the future
    //    upload handler needs; the id is stable, so retries are idempotent.
    await _syncQueue.enqueue(
      SyncOperation(
        id: _uuid.v4(),
        entityType: SyncEntityType.jobFile,
        entityId: fileId,
        type: SyncOperationType.upload,
        payload: <String, Object?>{
          'fileId': fileId,
          'jobId': jobId,
          'localPath': relativePath,
          'fileType': fileType.name,
          'fileName': sourceName,
          'sizeBytes': bytes.length,
          'mimeType': ?mimeType,
        },
        createdAt: now,
      ),
    );

    return fileId;
  }

  /// Metadata of one stored file, or `null` when unknown.
  Future<LocalJobFile?> getFile(String fileId) async {
    return (
      _database
          .select(_database.jobFilesTable)
          ..where((t) => t.id.equals(fileId))
    ).getSingleOrNull();
  }

  /// All files of a job, oldest first. A job may have any number of files of
  /// any kind — there is no one-before / one-after assumption.
  Future<List<LocalJobFile>> filesForJob(String jobId) async {
    return (
      _database
          .select(_database.jobFilesTable)
          ..where((t) => t.jobId.equals(jobId))
          ..orderBy(<OrderingTerm Function(JobFilesTable)>[
            (t) => OrderingTerm.asc(t.capturedAt),
            (t) => OrderingTerm.asc(t.id),
          ])
    ).get();
  }

  /// Called by the upload handler **after** the backend confirms the upload:
  /// stores the remote path and flips the row to `synced`.
  Future<void> markUploaded({
    required String fileId,
    required String remotePath,
  }) async {
    final DateTime now = _now();
    final t = _database.jobFilesTable;

    await (_database.update(t)..where((t) => t.id.equals(fileId))).write(
      JobFilesTableCompanion(
        remotePath: Value(remotePath),
        syncStatus: const Value('synced'),
        lastSyncedAt: Value(now),
      ),
    );
  }

  /// Deletes the local copy — but only after the upload has been confirmed.
  ///
  /// Throws [StateError] when the file is not `synced` yet: deleting an
  /// unsynced file would destroy the only copy of a captured photo.
  Future<void> deleteAfterConfirmedUpload(String fileId) async {
    final LocalJobFile? row = await getFile(fileId);
    if (row == null) {
      throw StateError('Unknown job file: $fileId');
    }
    if (row.syncStatus != 'synced' || row.remotePath == null) {
      throw StateError(
        'Job file $fileId has no confirmed remote upload; '
        'its local copy must not be deleted.',
      );
    }

    await _fileStorage.delete(row.localPath);

    await (_database.delete(_database.jobFilesTable)
      ..where((t) => t.id.equals(fileId))).go();
  }
}
