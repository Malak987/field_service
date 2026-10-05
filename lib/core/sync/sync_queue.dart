import 'package:field_service/core/sync/sync_operation.dart';

/// The durable, ordered queue of local changes that still have to reach the
/// backend.
///
/// Implementations must be backed by the local database, because the queue has
/// to survive app restarts, force closes and battery optimisations: an operation
/// that was accepted by the UI must never be lost because the app was killed.
///
/// The contract covers the full lifecycle the [SyncManager] drives: enqueue →
/// claim → push → synced/failed, plus the recovery and re-try transitions.
abstract interface class SyncQueue {
  /// Appends [operation] to the queue.
  ///
  /// Must be idempotent on `operation.id` so a retried enqueue cannot duplicate
  /// a change.
  Future<void> enqueue(SyncOperation operation);

  /// The oldest operation that still needs to be pushed, or `null` when the
  /// queue has nothing left. Oldest-first ordering is what keeps the local and
  /// remote states consistent (a create always precedes its updates).
  ///
  /// Operations whose [SyncOperation.dependsOn] parent has not reached
  /// `synced` yet are skipped until the parent completes.
  Future<SyncOperation?> nextPending();

  /// Number of operations still waiting to be pushed; drives the "N changes
  /// waiting to sync" indicator in the UI.
  Future<int> pendingCount();

  /// Number of operations in the failed state (awaiting a retry).
  Future<int> failedCount();

  /// The most recent failed operations, newest first, for diagnostics.
  Future<List<SyncOperation>> recentFailures({int limit = 20});

  /// Atomically flips one `pending` operation to `inProgress`.
  ///
  /// Returns `true` only for the caller that won the claim, so two sync runs
  /// can never push the same change concurrently.
  Future<bool> claimPending(String operationId);

  /// Returns an `inProgress` operation to `pending` when a run aborted before
  /// the push resolved (e.g. connectivity disappeared mid-run).
  Future<void> releaseInFlight(String operationId);

  /// Re-queues every `inProgress` row; called at start-up to recover
  /// operations that were in flight when the app was killed. Returns the
  /// number of recovered rows.
  Future<int> recoverInFlight();

  /// Moves every `failed` row back to `pending` for an explicit retry,
  /// keeping the attempt counters and the persisted error history.
  Future<void> requeueFailed();

  /// Marks an operation as accepted by the backend.
  Future<void> markSynced(String operationId);

  /// Records a failed attempt together with its reason.
  ///
  /// The operation stays in the queue and is retried later, so a transient
  /// network problem never loses a technician's work.
  Future<void> markFailed(String operationId, {required String errorMessage});

  /// Ids of [type]'s entities that still have an operation in `pending`,
  /// `inProgress` or `failed` state.
  ///
  /// Used by remote *pulls*: a local row with an unfinished operation must not
  /// be overwritten by backend data, because the local change still has to win
  /// its way onto the server (and a pending delete must not be resurrected).
  Future<Set<String>> unfinishedEntityIds(SyncEntityType type);
}
