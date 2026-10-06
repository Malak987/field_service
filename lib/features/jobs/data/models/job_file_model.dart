import 'package:field_service/core/database/app_database.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';

/// Maps `job_files` rows (local Drift rows and remote PostgREST rows) to the
/// domain [JobFile] entity.
class JobFileModel {
  const JobFileModel._();

  /// Maps a local Drift row (the sync architecture's source of truth on this
  /// device).
  static JobFile fromLocal(LocalJobFile row) {
    return JobFile(
      id: row.id,
      jobId: row.jobId,
      fileType: row.fileType,
      fileName: row.fileName,
      mimeType: row.mimeType,
      sizeBytes: row.sizeBytes,
      capturedAt: row.capturedAt,
      localPath: row.localPath,
      remotePath: row.remotePath,
      syncState: row.syncStatus == 'synced'
          ? JobFileSyncState.synced
          : JobFileSyncState.pending,
    );
  }

  /// Maps a remote `job_files` row as returned by PostgREST.
  ///
  /// Remote rows are always `synced` (the backend confirmed them) and have no
  /// local copy until the bytes are downloaded for display.
  static JobFile fromRemote(Map<String, dynamic> row) {
    return JobFile(
      id: row['id'] as String,
      jobId: row['job_id'] as String,
      fileType: row['file_type'] as String,
      fileName: row['file_name'] as String,
      mimeType: row['mime_type'] as String?,
      sizeBytes: (row['size_bytes'] as num?)?.toInt(),
      capturedAt: DateTime.parse(row['captured_at'] as String),
      remotePath: row['storage_path'] as String,
      syncState: JobFileSyncState.synced,
    );
  }
}
