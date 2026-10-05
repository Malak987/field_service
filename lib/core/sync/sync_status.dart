import 'package:equatable/equatable.dart';
import 'package:field_service/core/network/connectivity_service.dart';

/// The five states a sync indicator can show.
///
/// Derived from [SyncHealth] — never stored, so it can never drift out of
/// sync with the facts (connectivity, in-flight run, queue counts).
enum SyncDisplayStatus {
  /// Online and everything queued has reached the backend.
  synced,

  /// A push run is in progress right now.
  syncing,

  /// No usable internet (the queue keeps working locally meanwhile).
  offline,

  /// Online, with local changes still waiting to be pushed.
  pendingChanges,

  /// Online, with at least one operation that has failed and awaits a retry.
  failed,
}

/// A snapshot of the offline engine's state, enough for a compact indicator
/// ("Synced" / "Syncing…" / "Offline" / "N pending changes" / "Sync failed").
class SyncHealth extends Equatable {
  const SyncHealth({
    required this.networkStatus,
    this.isSyncing = false,
    this.pendingCount = 0,
    this.failedCount = 0,
    this.lastError,
  });

  /// Current connectivity (usable internet, not just an interface).
  final ConnectivityStatus networkStatus;

  /// Whether a push run is executing right now.
  final bool isSyncing;

  /// Operations still waiting to be pushed (`pending` + `inProgress`).
  final int pendingCount;

  /// Operations currently in the failed state (awaiting a retry).
  final int failedCount;

  /// Sanitised reason of the most recent failed attempt, when any.
  final String? lastError;

  /// The status a UI indicator should display.
  SyncDisplayStatus get displayStatus {
    if (isSyncing) {
      return SyncDisplayStatus.syncing;
    }
    if (networkStatus == ConnectivityStatus.offline) {
      return SyncDisplayStatus.offline;
    }
    if (failedCount > 0) {
      return SyncDisplayStatus.failed;
    }
    if (pendingCount > 0) {
      return SyncDisplayStatus.pendingChanges;
    }
    return SyncDisplayStatus.synced;
  }

  @override
  List<Object?> get props => <Object?>[
    networkStatus,
    isSyncing,
    pendingCount,
    failedCount,
    lastError,
  ];
}
