import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:field_service/core/database/app_database.dart';
import 'package:field_service/core/sync/sync_operation.dart';
import 'package:field_service/core/sync/sync_queue.dart';
import 'package:field_service/core/utils/logger.dart';

/// Drift-backed implementation of [SyncQueue].
///
/// Durable by construction: every state change is a committed SQLite write, so
/// the queue survives crashes, force closes and reboots. The class contains no
/// business logic and no backend access — it only stores, orders and
/// transitions rows.
class DriftSyncQueue implements SyncQueue {
  DriftSyncQueue(this._db, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;

  /// Maximum number of rows scanned while looking for the next executable
  /// operation. A dependency-blocked run of that length is not expected in
  /// practice; the scan cap keeps the queue from degrading under abuse.
  static const int _maxScan = 100;

  $SyncQueueTableTable get _table => _db.syncQueueTable;

  @override
  Future<void> enqueue(SyncOperation operation) async {
    await _db
        .into(_table)
        .insert(
          SyncQueueTableCompanion.insert(
            id: operation.id,
            entityType: operation.entityType.name,
            entityId: operation.entityId,
            operation: operation.type.name,
            payload: jsonEncode(operation.payload),
            dependsOn: Value(operation.dependsOn),
            status: Value(SyncOperationStatus.pending.name),
            attemptCount: const Value(0),
            lastAttemptAt: const Value(null),
            lastError: const Value(null),
            createdAt: operation.createdAt,
            updatedAt: _now(),
          ),
          // Idempotent on operation.id: a retried enqueue is a no-op, so a
          // crashed "enqueue then write" sequence can never duplicate a change.
          onConflict: DoNothing(),
        );
  }

  @override
  Future<SyncOperation?> nextPending() async {
    final $SyncQueueTableTable t = _table;

    final List<SyncQueueEntry> candidates = await (
      _db.select(t)
        ..where((t) => t.status.equals(SyncOperationStatus.pending.name))
        ..orderBy(<OrderingTerm Function($SyncQueueTableTable)>[
          (t) => OrderingTerm.asc(t.createdAt),
          (t) => OrderingTerm.asc(t.id),
        ])
        ..limit(_maxScan)
    ).get();

    for (final SyncQueueEntry entry in candidates) {
      final SyncOperation? operation = _safeToOperation(entry);
      if (operation == null) {
        continue; // corrupt/unknown row: logged, skipped, never stuck.
      }

      final String? dependsOn = entry.dependsOn;
      if (dependsOn != null) {
        final SyncQueueEntry? parent = await (
          _db.select(t)..where((t) => t.id.equals(dependsOn))
        ).getSingleOrNull();

        if (parent == null ||
            parent.status != SyncOperationStatus.synced.name) {
          // Parent not synced yet: this operation must wait.
          continue;
        }
      }

      return operation;
    }

    return null;
  }

  @override
  Future<int> pendingCount() {
    return _countByStatus(<String>[
      SyncOperationStatus.pending.name,
      SyncOperationStatus.inProgress.name,
    ]);
  }

  @override
  Future<int> failedCount() {
    return _countByStatus(<String>[SyncOperationStatus.failed.name]);
  }

  @override
  Future<List<SyncOperation>> recentFailures({int limit = 20}) async {
    final $SyncQueueTableTable t = _table;

    final List<SyncQueueEntry> entries = await (
      _db.select(t)
        ..where((t) => t.status.equals(SyncOperationStatus.failed.name))
        ..orderBy(<OrderingTerm Function($SyncQueueTableTable)>[(t) => OrderingTerm.desc(t.updatedAt)])
        ..limit(limit)
    ).get();

    return entries
        .map(_safeToOperation)
        .where((SyncOperation? op) => op != null)
        .map((op) => op!)
        .toList();
  }

  @override
  Future<bool> claimPending(String operationId) async {
    final $SyncQueueTableTable t = _table;

    // Conditional write: only the caller that finds the row still `pending`
    // flips it, so exactly one concurrent run can win the claim.
    final int affected = await (
      _db.update(t)
        ..where(
          (t) => t.id.equals(operationId) &
              t.status.equals(SyncOperationStatus.pending.name),
        )
    ).write(
      SyncQueueTableCompanion(
        status: Value(SyncOperationStatus.inProgress.name),
        lastAttemptAt: Value(_now()),
        updatedAt: Value(_now()),
      ),
    );

    return affected > 0;
  }

  @override
  Future<void> releaseInFlight(String operationId) async {
    final $SyncQueueTableTable t = _table;

    await (
      _db.update(t)
        ..where(
          (t) => t.id.equals(operationId) &
              t.status.equals(SyncOperationStatus.inProgress.name),
        )
    ).write(
      SyncQueueTableCompanion(
        status: Value(SyncOperationStatus.pending.name),
        updatedAt: Value(_now()),
      ),
    );
  }

  @override
  Future<int> recoverInFlight() async {
    final $SyncQueueTableTable t = _table;

    final int recovered = await (
      _db.update(t)
        ..where((t) => t.status.equals(SyncOperationStatus.inProgress.name))
    ).write(
      SyncQueueTableCompanion(
        status: Value(SyncOperationStatus.pending.name),
        updatedAt: Value(_now()),
      ),
    );

    return recovered;
  }

  @override
  Future<void> requeueFailed() async {
    final $SyncQueueTableTable t = _table;

    await (
      _db.update(t)
        ..where((t) => t.status.equals(SyncOperationStatus.failed.name))
    ).write(
      SyncQueueTableCompanion(
        status: Value(SyncOperationStatus.pending.name),
        updatedAt: Value(_now()),
      ),
    );
  }

  @override
  Future<void> markSynced(String operationId) async {
    final $SyncQueueTableTable t = _table;

    await (_db.update(t)..where((t) => t.id.equals(operationId))).write(
      SyncQueueTableCompanion(
        status: Value(SyncOperationStatus.synced.name),
        updatedAt: Value(_now()),
      ),
    );
  }

  @override
  Future<void> markFailed(
    String operationId, {
    required String errorMessage,
  }) async {
    final $SyncQueueTableTable t = _table;

    final SyncQueueEntry? entry = await (
      _db.select(t)..where((t) => t.id.equals(operationId))
    ).getSingleOrNull();

    // Defensive: the row should exist (we claimed it), but a missing row must
    // never throw out of the sync loop.
    if (entry == null) {
      AppLogger.warning(
        'Sync queue: markFailed called for unknown operation $operationId.',
      );
      return;
    }

    await (_db.update(t)..where((t) => t.id.equals(operationId))).write(
      SyncQueueTableCompanion(
        status: Value(SyncOperationStatus.failed.name),
        attemptCount: Value(entry.attemptCount + 1),
        lastAttemptAt: Value(_now()),
        lastError: Value(errorMessage),
        updatedAt: Value(_now()),
      ),
    );
  }

  @override
  Future<Set<String>> unfinishedEntityIds(SyncEntityType type) async {
    final $SyncQueueTableTable t = _table;

    final List<SyncQueueEntry> entries = await (
      _db.select(t)
        ..where(
          (t) =>
              t.entityType.equals(type.name) &
              t.status.isIn(<String>[
                SyncOperationStatus.pending.name,
                SyncOperationStatus.inProgress.name,
                SyncOperationStatus.failed.name,
              ]),
        )
    ).get();

    return entries.map((SyncQueueEntry e) => e.entityId).toSet();
  }

  // --- Internals ---------------------------------------------------------------

  Future<int> _countByStatus(List<String> statuses) async {
    final List<String> placeholders = List.filled(statuses.length, '?');
    final QueryRow row = await _db.customSelect(
      'SELECT COUNT(*) AS c FROM sync_queue '
      'WHERE status IN (${placeholders.join(', ')})',
      variables: statuses.map(Variable.new).toList(),
    ).getSingle();

    return row.read<int>('c');
  }

  /// Maps a row to a [SyncOperation]; returns `null` (with a warning) for rows
  /// whose enums no longer exist, so one corrupt row can never wedge the queue.
  SyncOperation? _safeToOperation(SyncQueueEntry entry) {
    try {
      return _toOperation(entry);
    } catch (error) {
      AppLogger.warning(
        'Sync queue: skipping unparseable row ${entry.id}.',
        error: error,
      );
      return null;
    }
  }

  SyncOperation _toOperation(SyncQueueEntry entry) {
    return SyncOperation(
      id: entry.id,
      entityType: SyncEntityType.values.byName(entry.entityType),
      entityId: entry.entityId,
      type: SyncOperationType.values.byName(entry.operation),
      payload: Map<String, Object?>.from(jsonDecode(entry.payload)),
      createdAt: entry.createdAt,
      dependsOn: entry.dependsOn,
      attempts: entry.attemptCount,
      status: SyncOperationStatus.values.byName(entry.status),
      lastAttemptAt: entry.lastAttemptAt,
      errorMessage: entry.lastError,
    );
  }
}
