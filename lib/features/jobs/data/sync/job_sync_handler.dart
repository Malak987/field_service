import 'package:field_service/core/sync/sync_handler.dart';
import 'package:field_service/core/sync/sync_operation.dart';
import 'package:field_service/features/jobs/data/datasources/jobs_remote_data_source.dart';
import 'package:field_service/features/jobs/data/repositories/jobs_repository_impl.dart';
import 'package:field_service/features/jobs/domain/entities/new_customer_draft.dart';

/// Pushes queued `job` operations to Supabase.
///
/// Registered in the shared [SyncHandlerRegistry] by the jobs DI module —
/// the same single integration point the Customers feature uses. Ordering,
/// claims and queue-state transitions stay with the `SyncManager`; this
/// class only performs the remote action.
///
/// Guarantees:
/// * **Idempotent.** Both actions are replay-safe by RPC design:
///   `start_job` returns an already-`in_progress` job unchanged (no second
///   `job_started` event, `started_at` never reset), and
///   `save_work_description` skips the update + event when the stored text
///   already equals the replayed text (no duplicate
///   `work_description_added` event). A retry after a lost ack therefore
///   cannot duplicate anything.
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

    if (operation.type == SyncOperationType.update &&
        action == JobsRepositoryImpl.saveWorkDescriptionAction) {
      final Object? text =
          operation.payload[JobsRepositoryImpl.workDescriptionKey];
      if (text is! String || text.trim().isEmpty) {
        return RemotePushResult.failure(
          'Job work description operation carries no text.',
        );
      }
      // The RPC stores the text + event atomically, or (on a replay of the
      // same text) observes it already stored — both count as synced.
      await _remote.saveWorkDescription(
        jobId: operation.entityId,
        workDescription: text,
      );
      return const RemotePushResult.ok();
    }

    if (operation.type == SyncOperationType.create &&
        action == JobsRepositoryImpl.technicianCreateCustomerAndJobAction) {
      // The whole "new customer + job" unit is ONE operation: the RPC inserts
      // both rows in a single transaction and is idempotent on the
      // client-generated job id, so a replay after a lost acknowledgement
      // returns the existing job instead of creating a second one.
      final Object? customerPayload =
          operation.payload[JobsRepositoryImpl.customerKey];
      if (customerPayload is! Map) {
        return RemotePushResult.failure(
          'Technician job creation operation carries no customer draft.',
        );
      }
      final _TechnicianJobDraft draft = _draftOf(operation);
      if (draft == null) {
        return RemotePushResult.failure(
          'Technician job creation operation is missing its ids.',
        );
      }

      await _remote.technicianCreateCustomerAndJob(
        jobId: draft.jobId,
        customerId: draft.customerId,
        customer: NewCustomerDraft.fromPayload(
          Map<String, Object?>.from(customerPayload),
        ),
        jobType: draft.jobType,
        description: draft.description,
      );
      return const RemotePushResult.ok();
    }

    if (operation.type == SyncOperationType.create &&
        action == JobsRepositoryImpl.technicianCreateJobAction) {
      final _TechnicianJobDraft? draft = _draftOf(operation);
      if (draft == null) {
        return RemotePushResult.failure(
          'Technician job creation operation is missing its ids.',
        );
      }

      await _remote.technicianCreateJobForCustomer(
        jobId: draft.jobId,
        customerId: draft.customerId,
        jobType: draft.jobType,
        description: draft.description,
      );
      return const RemotePushResult.ok();
    }

    return RemotePushResult.failure(
      'Unsupported job operation (type: ${operation.type.name}, '
      'action: $action).',
    );
  }

  /// Reads the shared part of a queued technician creation payload.
  ///
  /// `null` means the queue row is malformed — the manager then persists it
  /// as a failed (retryable, diagnosable) operation instead of pushing
  /// half-known data. A corrupt row is never silently "synced".
  static _TechnicianJobDraft? _draftOf(SyncOperation operation) {
    final Object? jobId = operation.payload[JobsRepositoryImpl.jobIdKey];
    final Object? customerId =
        operation.payload[JobsRepositoryImpl.customerIdKey];
    final Object? jobType = operation.payload[JobsRepositoryImpl.jobTypeKey];
    final Object? description =
        operation.payload[JobsRepositoryImpl.descriptionKey];

    if (jobId is! String || customerId is! String || jobType is! String) {
      return null;
    }

    return _TechnicianJobDraft(
      jobId: jobId,
      customerId: customerId,
      jobType: jobType,
      description: description is String ? description : null,
    );
  }
}

/// The arguments every queued technician creation carries (the customer
/// draft travels separately, nested under its own payload key).
class _TechnicianJobDraft {
  const _TechnicianJobDraft({
    required this.jobId,
    required this.customerId,
    required this.jobType,
    required this.description,
  });

  final String jobId;
  final String customerId;
  final String jobType;
  final String? description;
}
