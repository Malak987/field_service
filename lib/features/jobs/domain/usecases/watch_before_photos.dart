import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Reactive stream of a job's before photos (see [GetBeforePhotos] for the
/// merge semantics). Emits immediately from the local database and again on
/// every local change — a newly captured photo appears right away and its
/// sync state flips to `synced` the moment the shared sync engine confirms
/// the upload.
class WatchBeforePhotos {
  const WatchBeforePhotos(this._repository);

  final JobsRepository _repository;

  Stream<List<JobFile>> call(String jobId) {
    return _repository.watchBeforePhotos(jobId);
  }
}
