// ignore_for_file: prefer_initializing_formals
import 'package:field_service/core/database/app_database.dart';
import 'package:field_service/core/storage/file_storage.dart';
import 'package:field_service/core/storage/local_file_storage.dart';
import 'package:field_service/core/sync/sync_handler.dart';
import 'package:field_service/core/sync/sync_operation.dart';
import 'package:field_service/features/jobs/data/datasources/job_files_remote_data_source.dart';

/// Pushes queued `jobFile` upload operations (before photos) to Supabase.
///
/// Registered in the shared [SyncHandlerRegistry] by the jobs DI module —
/// the same single integration point the Jobs and Customers features use.
/// Ordering, claims and queue-state transitions stay with the `SyncManager`;
/// this class only performs the remote work:
///
/// 1. read the registered local row + bytes (app-owned storage),
/// 2. upload the bytes to Storage at the deterministic path
///    `jobs/{job_id}/{file_type}/{file_id}{ext}` with **upsert**,
/// 3. register the file through the `register_job_file` RPC (ownership +
///    `in_progress` rules + idempotent row insert + exactly one
///    `before_photo_captured` event, all server-side),
/// 4. mark the local row `synced` with the confirmed remote path.
///
/// Idempotency: every step is keyed on the stable client-generated file id.
/// A retried operation uploads to the same object path (upsert), the RPC's
/// `ON CONFLICT DO NOTHING` returns without a second row or event, and
/// [LocalFileStorage.markUploaded] simply rewrites the same values.
///
/// Failures: expected problems (missing local row/bytes) are returned as
/// [RemotePushResult.failure]; backend exceptions rethrow, so the manager
/// persists the queue row as `failed` (retryable) — never silently dropped,
/// never fake-synced.
class JobFileSyncHandler implements SyncOperationHandler {
  JobFileSyncHandler({
    required LocalFileStorage localFiles,
    required FileStorage fileStorage,
    required JobFilesRemoteDataSource remote,
  }) : _localFiles = localFiles,
       _fileStorage = fileStorage,
       _remote = remote;

  final LocalFileStorage _localFiles;
  final FileStorage _fileStorage;
  final JobFilesRemoteDataSource _remote;

  @override
  Future<RemotePushResult> push(SyncOperation operation) async {
    if (operation.entityType != SyncEntityType.jobFile) {
      return RemotePushResult.failure(
        'JobFileSyncHandler received a "${operation.entityType.name}" '
        'operation.',
      );
    }
    if (operation.type != SyncOperationType.upload) {
      return RemotePushResult.failure(
        'Unsupported job file operation type: ${operation.type.name}.',
      );
    }

    final String fileId = operation.entityId;
    final LocalJobFile? row = await _localFiles.getFile(fileId);
    if (row == null) {
      // The row vanished (e.g. delete-after-confirmed-upload ran already):
      // there is nothing to push.
      return const RemotePushResult.ok();
    }

    final List<int>? bytes = await _fileStorage.read(row.localPath);
    if (bytes == null) {
      return RemotePushResult.failure(
        'The local copy of this file is missing; nothing to upload.',
      );
    }

    final String storagePath = JobFilesRemoteDataSource.storagePathFor(
      jobId: row.jobId,
      fileType: row.fileType,
      fileId: row.id,
      extension: extensionOfLocalPath(row.localPath),
    );

    // 1) Bytes to Storage (upsert: retries hit the same object).
    await _remote.uploadPhotoBytes(
      storagePath: storagePath,
      bytes: bytes,
      mimeType: row.mimeType,
    );

    // 2) Metadata + `before_photo_captured` event through the secure RPC.
    //    The ORIGINAL captured_at travels with the call; the server stores
    //    it and uses it as the event's occurred_at.
    await _remote.registerJobFile(
      fileId: row.id,
      jobId: row.jobId,
      fileType: row.fileType,
      storagePath: storagePath,
      fileName: row.fileName,
      mimeType: row.mimeType,
      sizeBytes: row.sizeBytes,
      capturedAt: row.capturedAt,
    );

    // 3) Confirmed: store the remote path, flip the row to `synced`.
    await _localFiles.markUploaded(fileId: fileId, remotePath: storagePath);

    return const RemotePushResult.ok();
  }
}
