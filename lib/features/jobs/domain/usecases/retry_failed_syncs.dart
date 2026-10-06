import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Re-queues every failed sync operation (upload failures of before photos,
/// refused pushes, …) and gives the shared sync engine a nudge — the
/// "Retry" action of the Before Photos section. Uses the existing
/// `SyncProcessor`; no second retry mechanism is introduced.
class RetryFailedSyncs {
  const RetryFailedSyncs(this._repository);

  final JobsRepository _repository;

  Future<void> call() {
    return _repository.retryFailedSyncs();
  }
}
