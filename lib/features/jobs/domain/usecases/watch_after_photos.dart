import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Reactive stream of a job's after photos (same merge semantics as
/// [WatchBeforePhotos], filtered to `file_type = 'after'`). Emits
/// immediately from the local database and again on every local change — a
/// newly captured photo appears right away and its sync state flips to
/// `synced` the moment the shared sync engine confirms the upload.
class WatchAfterPhotos {
  const WatchAfterPhotos(this._repository);

  final JobsRepository _repository;

  Stream<List<JobFile>> call(String jobId) {
    return _repository.watchAfterPhotos(jobId);
  }
}
