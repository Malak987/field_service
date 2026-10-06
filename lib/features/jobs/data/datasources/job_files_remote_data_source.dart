import 'dart:typed_data';

import 'package:field_service/features/jobs/data/models/job_file_model.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Remote data source contract for job files (this phase: before photos).
///
/// Two remote surfaces, both authorized server-side:
/// * `public.job_files` — reads are protected by RLS (assigned active
///   employee or active admin); the ONLY write path is the
///   `register_job_file` SECURITY DEFINER RPC.
/// * the private `job-files` Storage bucket — object paths follow
///   `jobs/{job_id}/{file_type}/{file_id}{ext}` and storage policies enforce
///   the same job ownership.
abstract interface class JobFilesRemoteDataSource {
  /// The Storage bucket holding job files.
  static const String bucket = 'job-files';

  /// Deterministic, identity-based Storage object path:
  /// `jobs/{job_id}/{file_type}/{file_id}{ext}`.
  ///
  /// The stable client-generated [fileId] — never the device filename — is
  /// the storage identity, which is what makes retried uploads upsert the
  /// same object instead of creating a second one.
  static String storagePathFor({
    required String jobId,
    required String fileType,
    required String fileId,
    String extension = '',
  }) {
    return 'jobs/$jobId/$fileType/$fileId$extension';
  }

  /// Before photos of [jobId] as registered on the backend.
  ///
  /// Authorization is enforced by the `job_files` SELECT policy: a caller
  /// who is not the job's assigned active employee (or an active admin)
  /// simply gets zero rows.
  Future<List<JobFile>> getJobBeforePhotos(String jobId);

  /// Uploads the photo bytes to Storage at [storagePath] with upsert
  /// semantics — a retry of the same file id overwrites the same object.
  Future<void> uploadPhotoBytes({
    required String storagePath,
    required List<int> bytes,
    String? mimeType,
  });

  /// Registers the uploaded file through the `register_job_file` RPC — the
  /// only write path. The RPC resolves the caller's identity itself,
  /// verifies job ownership and `in_progress` status, inserts the row
  /// idempotently (on the stable [fileId]) and appends exactly one
  /// `before_photo_captured` event whose `occurred_at` is [capturedAt] —
  /// the original capture time, never the upload time.
  Future<void> registerJobFile({
    required String fileId,
    required String jobId,
    required String fileType,
    required String storagePath,
    required String fileName,
    String? mimeType,
    int? sizeBytes,
    required DateTime capturedAt,
  });

  /// Downloads the bytes of a remote object (viewing a photo captured on
  /// another device).
  Future<Uint8List> downloadPhotoBytes(String storagePath);
}

class JobFilesRemoteDataSourceImpl implements JobFilesRemoteDataSource {
  JobFilesRemoteDataSourceImpl(this.supabase);

  final SupabaseClient supabase;

  /// Small in-memory cache so a grid of photos does not re-download the same
  /// object on every rebuild. Intentionally tiny and dumb: display cache
  /// only, never a second data layer.
  final Map<String, Uint8List> _downloadCache = <String, Uint8List>{};
  static const int _downloadCacheLimit = 24;

  @override
  Future<List<JobFile>> getJobBeforePhotos(String jobId) async {
    final List<Map<String, dynamic>> rows = await supabase
        .from('job_files')
        .select()
        .eq('job_id', jobId)
        .eq('file_type', 'before')
        .order('captured_at');

    return rows.map(JobFileModel.fromRemote).toList();
  }

  @override
  Future<void> uploadPhotoBytes({
    required String storagePath,
    required List<int> bytes,
    String? mimeType,
  }) async {
    await supabase.storage
        .from(JobFilesRemoteDataSource.bucket)
        .uploadBinary(
          storagePath,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(
            contentType: mimeType ?? 'image/jpeg',
            // Retries of the same file id overwrite the same object — there
            // is never a second object for one captured photo.
            upsert: true,
          ),
        );
  }

  @override
  Future<void> registerJobFile({
    required String fileId,
    required String jobId,
    required String fileType,
    required String storagePath,
    required String fileName,
    String? mimeType,
    int? sizeBytes,
    required DateTime capturedAt,
  }) async {
    // The client sends the stable file id and the ORIGINAL capture time;
    // ownership, status rules and the event are all decided server-side.
    await supabase.rpc(
      'register_job_file',
      params: <String, dynamic>{
        'p_file_id': fileId,
        'p_job_id': jobId,
        'p_file_type': fileType,
        'p_storage_path': storagePath,
        'p_file_name': fileName,
        'p_mime_type': mimeType,
        'p_size_bytes': sizeBytes,
        'p_captured_at': capturedAt.toIso8601String(),
      },
    );
  }

  @override
  Future<Uint8List> downloadPhotoBytes(String storagePath) async {
    final Uint8List? cached = _downloadCache[storagePath];
    if (cached != null) {
      return cached;
    }

    final Uint8List bytes = await supabase.storage
        .from(JobFilesRemoteDataSource.bucket)
        .download(storagePath);

    if (_downloadCache.length >= _downloadCacheLimit) {
      _downloadCache.remove(_downloadCache.keys.first);
    }
    _downloadCache[storagePath] = bytes;
    return bytes;
  }
}

/// Derives a short, safe file extension from a local relative path
/// (`.jpg`, `.png`, …) — empty when unknown. Used to build Storage paths.
String extensionOfLocalPath(String localPath) {
  final String extension = p.extension(localPath).toLowerCase();
  const Set<String> allowed = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.heic',
    '.heif',
  };
  return allowed.contains(extension) ? extension : '';
}
