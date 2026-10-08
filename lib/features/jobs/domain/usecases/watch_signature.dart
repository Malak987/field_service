import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Reactive stream of a job's customer signature (same merge semantics as
/// [WatchBeforePhotos], filtered to `file_type = 'signature'`). Emits
/// immediately from the local database and again on every local change — a
/// newly captured signature appears right away (even offline) and its sync
/// state flips to `synced` the moment the shared sync engine confirms the
/// upload.
class WatchSignature {
  const WatchSignature(this._repository);

  final JobsRepository _repository;

  Stream<List<JobFile>> call(String jobId) {
    return _repository.watchSignatureFiles(jobId);
  }
}
