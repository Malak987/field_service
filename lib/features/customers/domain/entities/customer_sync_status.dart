/// Lifecycle of one local `customers` row with respect to the backend.
///
/// This mirrors the `sync_status` string stored on the Drift row (a local-only
/// column that never reaches Supabase). It is part of the domain model
/// because the offline-first UI must render it next to every customer — it is
/// a user-visible fact about the record, not an implementation detail.
enum CustomerSyncStatus {
  /// The row matches the backend (pushed or pulled).
  synced,

  /// A local change (create/update) has not been accepted by the backend yet.
  pending,

  /// A push for this row is executing right now.
  inProgress,

  /// The last push attempt failed; the change is kept and retried by the
  /// sync engine (see `SyncManager.retryFailedOperations`).
  failed,
}
