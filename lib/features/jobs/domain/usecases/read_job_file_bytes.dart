import 'dart:typed_data';

import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Reads the image bytes of a before photo for display.
///
/// Local files are read from app-owned storage; backend-only files (captured
/// on another device, viewed e.g. by an admin) are downloaded through the
/// existing Supabase Storage integration, whose object policies enforce the
/// same job ownership as the `job_files` table.
class ReadJobFileBytes {
  const ReadJobFileBytes(this._repository);

  final JobsRepository _repository;

  /// Returns the bytes, or `null` when the file is no longer available.
  Future<Uint8List?> call(JobFile file) {
    return _repository.readPhotoBytes(file);
  }
}
