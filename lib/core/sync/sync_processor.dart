/// Drives the offline-first push flow.
///
/// The flow it owns (not implemented in this phase):
///
/// ```text
/// 1. take the oldest pending operation from the sync queue
/// 2. wait until connectivity reports usable internet access
/// 3. push the change through the Data layer
/// 4. mark it synced, or failed (incrementing the attempt counter)
/// ```
///
/// Phase 3 status: **interface only.** The engine itself — background scheduling,
/// retry/backoff, conflict policy and Supabase calls — belongs to the
/// synchronisation phase, so that this phase stays completely free of backend
/// code. Declaring the contract now is what lets the UI and the data sources be
/// written against it later without redesign.
abstract interface class SyncProcessor {
  /// Whether a push run is currently in progress (drives the "Syncing…" state).
  bool get isSyncing;

  /// Pushes everything currently queued, oldest first.
  ///
  /// Safe to call repeatedly: implementations must serialise concurrent runs and
  /// stop cleanly when connectivity disappears mid-run, leaving the remaining
  /// operations pending.
  Future<void> processPendingOperations();

  /// Re-queues operations that previously failed, for an explicit user action
  /// ("Try again") after a long offline period.
  Future<void> retryFailedOperations();
}
