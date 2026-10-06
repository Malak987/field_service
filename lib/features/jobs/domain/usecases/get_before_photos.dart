import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Returns the before photos of a job as a one-shot merged snapshot:
/// everything stored locally on this device (including not-yet-uploaded
/// photos) plus backend-registered photos captured elsewhere, deduplicated
/// by the stable file id and ordered by capture time.
///
/// Offline-safe: when the backend is unreachable the local photos are still
/// returned — a captured photo is never hidden because there is no signal.
class GetBeforePhotos {
  const GetBeforePhotos(this._repository);

  final JobsRepository _repository;

  Future<List<JobFile>> call(String jobId) {
    return _repository.getBeforePhotos(jobId);
  }
}
