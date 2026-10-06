import 'package:field_service/core/sync/sync_handler.dart';
import 'package:field_service/core/sync/sync_operation.dart';
import 'package:field_service/features/jobs/data/datasources/jobs_remote_data_source.dart';
import 'package:field_service/features/jobs/data/repositories/jobs_repository_impl.dart';

/// Pushes queued `job` operations to Supabase.
///
/// Registered in the shared [SyncHandlerRegistry] by the jobs DI module —
/// the same single integration point the Customers feature uses. Ordering,
/// claims and queue-state transitions stay with the `SyncManager`; this
/// class only performs the remote action.
///
/// Guarantees:
/// * **Idempotent.** The only action today is `start_job`, and the RPC
///   itself is replay-safe: an already-`in_progress` job is returned
///   unchanged (no second `job_started` event, `started_at` never reset).
///   A retry after a lost ack therefore cannot duplicate anything.
/// * **Server-authoritative.** The handler sends only the job id; status,
///   `started_at`, `updated_at` and the event are all created by the
///   database (inside one transaction), never by client-provided values.
/// * **Retry-safe failures.** A refused push (not the assigned employee,
///   unassigned job, invalid state) rethrows, so the manager persists the
///   queue row as `failed` and it stays retryable — never silently dropped,
///   never marked synced.
class JobSyncHandler implements SyncOperationHandler {
  JobSyncHandler({required this._remote});

  final JobsRemoteDataSource _remote;

  @override
  Future<RemotePushResult> push(SyncOperation operation) async {
    if (operation.entityType != SyncEntityType.job) {
      return RemotePushResult.failure(
        'JobSyncHandler received a "${operation.entityType.name}" operation.',
      );
    }

    final Object? action = operation.payload[JobsRepositoryImpl.actionKey];

    if (operation.type == SyncOperationType.update &&
        action == JobsRepositoryImpl.startJobAction) {
      // The RPC either applies the start atomically or (on a replay)
      // observes the already-started job — both count as synced.
      await _remote.startJob(operation.entityId);
      return const RemotePushResult.ok();
    }

    return RemotePushResult.failure(
      'Unsupported job operation (type: ${operation.type.name}, '
      'action: $action).',
    );
  }
}
