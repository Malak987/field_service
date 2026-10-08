import 'package:field_service/core/database/app_database.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:path/path.dart' as p;

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
  /// local copy until the bytes are downloaded for display — [JobFile.localPath]
  /// stays `null`, which is exactly what routes `readPhotoBytes` to the
  /// Supabase Storage download (the cross-device / data-reset restore path).
  ///
  /// The live `public.job_files` schema persists identity + classification
  /// only (id, job_id, file_type, storage_path, created_at, captured_at) —
  /// there are NO file_name/mime_type/size_bytes columns on the backend.
  /// The display name is therefore derived from the storage object itself;
  /// optional metadata tolerates absent keys instead of crashing the whole
  /// remote merge (the old hard cast on `file_name` threw a TypeError for
  /// every remote row and silently hid all backend-registered files).
  static JobFile fromRemote(Map<String, dynamic> row) {
    final String storagePath = row['storage_path'] as String;
    return JobFile(
      id: row['id'] as String,
      jobId: row['job_id'] as String,
      fileType: row['file_type'] as String,
      fileName: p.basename(storagePath),
      mimeType: row['mime_type'] as String?,
      sizeBytes: (row['size_bytes'] as num?)?.toInt(),
      capturedAt: DateTime.parse(row['captured_at'] as String),
      remotePath: storagePath,
      syncState: JobFileSyncState.synced,
    );
  }
}
