import 'package:field_service/core/sync/sync_operation.dart';

/// The durable, ordered queue of local changes that still have to reach the
/// backend.
///
/// Implementations must be backed by the local database, because the queue has
/// to survive app restarts, force closes and battery optimisations: an operation
/// that was accepted by the UI must never be lost because the app was killed.
///
/// Implemented by `DriftSyncQueue` (local schema phase); the `SyncManager`
/// is the consumer side.
abstract interface class SyncQueue {
  /// Appends [operation] to the queue.
  ///
  /// Must be idempotent on `operation.id` so a retried enqueue cannot duplicate
  /// a change.
  ///
  /// When [SyncOperation.dependsOn] is set, the referenced operation must
  /// already be in the queue (enqueue parents before children).
  Future<void> enqueue(SyncOperation operation);

  /// The oldest operation that still needs to be pushed, or `null` when the
  /// queue has nothing left. Oldest-first ordering is what keeps the local and
  /// remote states consistent (a create always precedes its updates).
  ///
  /// Dependency-aware: an operation whose `dependsOn` parent is not yet
  /// `synced` is skipped until the parent is.
  Future<SyncOperation?> nextPending();

  /// Number of operations still waiting to be pushed (`pending` plus
  /// `inProgress`); drives the "N changes waiting to sync" indicator in the UI.
  Future<int> pendingCount();

  /// Number of operations that are currently `failed`; drives the sync
  /// indicator's failed state and future admin/debug screens.
  Future<int> failedCount();

  /// The most recent failed operations, newest first.
  ///
  /// Exposed so a future Admin/debug screen can show what is blocked and why
  /// without any special access to the database.
  Future<List<SyncOperation>> recentFailures({int limit = 20});

  /// Claims [operationId] for processing: atomically transitions it from
  /// `pending` to `inProgress`.
  ///
  /// Returns `false` when the operation was not `pending` (already claimed by
  /// another run or already resolved) — this is the double-processing guard.
  Future<bool> claimPending(String operationId);

  /// Releases an operation that was claimed but could not be processed
  /// (e.g. connectivity dropped mid-run), putting it back to `pending`.
  Future<void> releaseInFlight(String operationId);

  /// Recovers the queue after a restart: every operation left `inProgress`
  /// by a killed run becomes `pending` again. Returns how many were recovered.
  Future<int> recoverInFlight();

  /// Requeues all `failed` operations for a retry, preserving their attempt
  /// counters and error history.
  Future<void> requeueFailed();

  /// Marks an operation as accepted by the backend.
  Future<void> markSynced(String operationId);

  /// Records a failed attempt together with its reason.
  ///
  /// The operation stays in the queue and is retried later, so a transient
  /// network problem never loses a technician's work. The attempt counter is
  /// incremented and [errorMessage] is persisted (sanitised).
  Future<void> markFailed(String operationId, {required String errorMessage});
}
