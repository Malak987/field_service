// ignore_for_file: prefer_initializing_formals
import 'package:field_service/core/database/app_database.dart';
import 'package:field_service/core/storage/file_storage.dart';
import 'package:field_service/core/storage/local_file_storage.dart';
import 'package:field_service/core/sync/sync_handler.dart';
import 'package:field_service/core/sync/sync_operation.dart';
import 'package:field_service/core/utils/logger.dart';
import 'package:field_service/features/jobs/data/datasources/job_files_remote_data_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

    // ---------------------------------------------------------------------
    // TEMPORARY DEBUG-ONLY diagnostics (JOB_FILE_SYNC): identify the exact
    // failing stage of the job-file upload. Debug-build logging only
    // (`AppLogger.debug` is stripped in release); no control-flow change —
    // every stage keeps its original result/rethrow semantics. Logs ids and
    // backend error text only; never tokens, signed URLs or file bytes.
    // Remove this block once the failing stage is confirmed.
    // ---------------------------------------------------------------------
    AppLogger.debug(
      'JOB_FILE_SYNC\n'
      'fileId=$fileId\n'
      'jobId=${row.jobId}\n'
      'fileType=${row.fileType}',
    );

    final List<int>? bytes = await _fileStorage.read(row.localPath);
    if (bytes == null) {
      AppLogger.debug('JOB_FILE_SYNC STAGE=read_local_file\nfailure');
      return RemotePushResult.failure(
        'The local copy of this file is missing; nothing to upload.',
      );
    }
    AppLogger.debug('JOB_FILE_SYNC STAGE=read_local_file\nsuccess');

    final String storagePath = JobFilesRemoteDataSource.storagePathFor(
      jobId: row.jobId,
      fileType: row.fileType,
      fileId: row.id,
      extension: extensionOfLocalPath(row.localPath),
    );
    AppLogger.debug('JOB_FILE_SYNC storagePath=$storagePath');

    // 1) Bytes to Storage (upsert: retries hit the same object).
    try {
      await _remote.uploadPhotoBytes(
        storagePath: storagePath,
        bytes: bytes,
        mimeType: row.mimeType,
      );
      AppLogger.debug('JOB_FILE_SYNC STAGE=storage_upload\nsuccess');
    } catch (error) {
      AppLogger.debug(_jobFileSyncUploadFailure(error));
      rethrow;
    }

    // 2) Metadata + `before_photo_captured` event through the secure RPC.
    //    The ORIGINAL captured_at travels with the call; the server stores
    //    it and uses it as the event's occurred_at.
    try {
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
      AppLogger.debug('JOB_FILE_SYNC STAGE=register_job_file\nsuccess');
    } catch (error) {
      AppLogger.debug(_jobFileSyncRpcFailure(error));
      rethrow;
    }

    // 3) Confirmed: store the remote path, flip the row to `synced`.
    try {
      await _localFiles.markUploaded(fileId: fileId, remotePath: storagePath);
      AppLogger.debug('JOB_FILE_SYNC STAGE=mark_uploaded\nsuccess');
    } catch (error) {
      AppLogger.debug(_jobFileSyncMarkUploadedFailure(error));
      rethrow;
    }

    return const RemotePushResult.ok();
  }

  /// TEMPORARY DEBUG-ONLY (see `push`): structured failure log for the
  /// Storage upload stage. Preserves the backend-provided status/message —
  /// no secrets, tokens or signed URLs are part of these fields.
  String _jobFileSyncUploadFailure(Object error) {
    if (error is StorageException) {
      return 'JOB_FILE_SYNC STAGE=storage_upload\n'
          'failure\n'
          'exceptionType=StorageException\n'
          'exceptionMessage=${error.message}\n'
          'statusCode=${error.statusCode ?? ''}';
    }
    return 'JOB_FILE_SYNC STAGE=storage_upload\n'
        'failure\n'
        'exceptionType=${error.runtimeType}\n'
        'exceptionMessage=$error\n'
        'statusCode=';
  }

  /// TEMPORARY DEBUG-ONLY (see `push`): structured failure log for the
  /// `register_job_file` RPC stage.
  String _jobFileSyncRpcFailure(Object error) {
    if (error is PostgrestException) {
      return 'JOB_FILE_SYNC STAGE=register_job_file\n'
          'failure\n'
          'exceptionType=PostgrestException\n'
          'exceptionMessage=${error.message}\n'
          'code=${error.code}';
    }
    return 'JOB_FILE_SYNC STAGE=register_job_file\n'
        'failure\n'
        'exceptionType=${error.runtimeType}\n'
        'exceptionMessage=$error\n'
        'code=';
  }

  /// TEMPORARY DEBUG-ONLY (see `push`): structured failure log for the
  /// local `markUploaded` stage.
  String _jobFileSyncMarkUploadedFailure(Object error) {
    return 'JOB_FILE_SYNC STAGE=mark_uploaded\n'
        'failure\n'
        'exceptionType=${error.runtimeType}\n'
        'exceptionMessage=$error';
  }
}
