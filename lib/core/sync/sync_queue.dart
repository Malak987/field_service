import 'package:field_service/core/sync/sync_operation.dart';

/// The durable, ordered queue of local changes that still have to reach the
/// backend.
///
/// Implementations must be backed by the local database, because the queue has
/// to survive app restarts, force closes and battery optimisations: an operation
/// that was accepted by the UI must never be lost because the app was killed.
///
/// Phase 3 status: **interface only.** The Drift-backed implementation arrives
/// with the local schema; the sync engine phase implements the consumer side.
abstract interface class SyncQueue {
  /// Appends [operation] to the queue.
  ///
  /// Must be idempotent on `operation.id` so a retried enqueue cannot duplicate
  /// a change.
  Future<void> enqueue(SyncOperation operation);

  /// The oldest operation that still needs to be pushed, or `null` when the
  /// queue has nothing left. Oldest-first ordering is what keeps the local and
  /// remote states consistent (a create always precedes its updates).
  Future<SyncOperation?> nextPending();

  /// Number of operations still waiting to be pushed; drives the "N changes
  /// waiting to sync" indicator in the UI.
  Future<int> pendingCount();

  /// Marks an operation as accepted by the backend.
  Future<void> markSynced(String operationId);

  /// Records a failed attempt together with its reason.
  ///
  /// The operation stays in the queue and is retried later, so a transient
  /// network problem never loses a technician's work.
  Future<void> markFailed(String operationId, {required String errorMessage});
}
