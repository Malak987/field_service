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
  DriftSyncQueue(
    this._db, {
    DateTime Function()? now,
    String? Function()? currentUserId,
  }) : _now = now ?? DateTime.now,
       _currentUserId = currentUserId ?? (() => null);

  final AppDatabase _db;
  final DateTime Function() _now;
  final String? Function() _currentUserId;

  /// Maximum number of rows scanned while looking for the next executable
  /// operation. A dependency-blocked run of that length is not expected in
  /// practice; the scan cap keeps the queue from degrading under abuse.
  static const int _maxScan = 100;

  $SyncQueueTableTable get _table => _db.syncQueueTable;

  @override
  Future<void> enqueue(SyncOperation operation) async {
    final String? ownerId = _currentUserId();
    final String? jobId = _jobIdFor(operation);
    await _db.transaction(() async {
      bool blockedByRetention = false;
      if (jobId != null) {
        final QueryRow? knownJob = await _db.customSelect(
          'SELECT retention_state FROM local_job_retention WHERE job_id = ?',
          variables: <Variable<Object>>[Variable<String>(jobId)],
        ).getSingleOrNull();
        final String? retentionState = knownJob?.read<String?>('retention_state');
        if (retentionState == 'purged') {
          throw StateError('A locally expired task cannot be recreated by retry.');
        }
        blockedByRetention = retentionState != null && retentionState != 'active';
      }
      final bool alreadyStored = await _db.customSelect(
        'SELECT 1 FROM sync_queue WHERE id = ?',
        variables: <Variable<Object>>[Variable<String>(operation.id)],
      ).getSingleOrNull() != null;
      final int inserted = await _db.into(_table).insert(
          SyncQueueTableCompanion.insert(
            id: operation.id,
            entityType: operation.entityType.name,
            entityId: operation.entityId,
            operation: operation.type.name,
            payload: jsonEncode(operation.payload),
            dependsOn: Value(operation.dependsOn),
            status: Value(
              blockedByRetention
                  ? SyncOperationStatus.blocked.name
                  : SyncOperationStatus.pending.name,
            ),
            attemptCount: const Value(0),
            lastAttemptAt: const Value(null),
            lastError: Value(
              blockedByRetention ? 'terminal:job_retention_not_active' : null,
            ),
            createdAt: operation.createdAt,
            updatedAt: _now(),
          ),
          // Idempotent on operation.id: a retried enqueue is a no-op, so a
          // crashed "enqueue then write" sequence can never duplicate a change.
          onConflict: DoNothing(),
        );
      if (alreadyStored || inserted == 0) return;

      await _db.customStatement(
        'INSERT OR IGNORE INTO sync_operation_scope '
        '(operation_id, job_id, owner_user_id, created_at_source, created_at) '
        'VALUES (?, ?, ?, ?, ?)',
        <Object?>[
          operation.id,
          jobId,
          ownerId,
          operation.entityType == SyncEntityType.job &&
                  operation.type == SyncOperationType.create
              ? _creationTimeSource(operation)
              : 'queue_operation',
          operation.entityType == SyncEntityType.job &&
                  operation.type == SyncOperationType.create
              ? _creationTime(operation)?.toIso8601String()
              : null,
        ],
      );

      if (operation.entityType == SyncEntityType.job &&
          operation.type == SyncOperationType.create) {
        final DateTime? createdAt = _creationTime(operation);
        if (createdAt != null) {
          final DateTime utc = createdAt.toUtc();
          await _db.customStatement(
            '''INSERT OR IGNORE INTO local_job_retention
              (job_id, original_created_at, created_at_source,
               created_by_user_id, authorized_sync_user_id, identity_state,
               task_state, expires_at, retention_state, cleanup_step, updated_at)
              VALUES (?, ?, ?, ?, ?, ?, 'local_pending',
                      ?, 'active', 'not_started', ?)''',
            <Object?>[
              operation.entityId,
              utc.toIso8601String(),
              _creationTimeSource(operation),
              ownerId,
              ownerId,
              ownerId == null ? 'owner_unknown' : 'verified',
              _oneCalendarYearLater(utc).toIso8601String(),
              _now().toUtc().toIso8601String(),
            ],
          );
        }
      }
    });
  }

  @override
  Future<SyncOperation?> nextPending() async {
    final String? currentUserId = _currentUserId();
    if (currentUserId == null || currentUserId.isEmpty) return null;
    final $SyncQueueTableTable t = _table;

    final List<SyncQueueEntry> candidates =
        await (_db.select(t)
              ..where((t) => t.status.equals(SyncOperationStatus.pending.name))
              ..orderBy(<OrderingTerm Function($SyncQueueTableTable)>[
                (t) => OrderingTerm.asc(t.createdAt),
                (t) => OrderingTerm.asc(t.id),
              ])
              ..limit(_maxScan))
            .get();

    for (final SyncQueueEntry entry in candidates) {
      final QueryRow? scope = await _scope(entry.id);
      // Pre-existing rows intentionally have no scope and are quarantined.
      if (scope == null || scope.read<String?>('owner_user_id') != currentUserId) {
        continue;
      }
      final String? jobId = scope.read<String?>('job_id');
      if (jobId != null) {
        final QueryRow? retention = await _retention(jobId);
        if (retention?.read<String>('retention_state') != 'active') continue;
        final String? expiry = retention?.read<String?>('expires_at');
        if (expiry != null && DateTime.tryParse(expiry)?.isAfter(_now()) != true) {
          await _blockExpiredJob(jobId);
          continue;
        }
        final String? authorized = retention?.read<String?>('authorized_sync_user_id');
        if (authorized != null && authorized != currentUserId) continue;
      }
      final SyncOperation? operation = _safeToOperation(
        entry,
        ownerUserId: currentUserId,
        jobId: jobId,
      );
      if (operation == null) {
        continue; // corrupt/unknown row: logged, skipped, never stuck.
      }

      final String? dependsOn = entry.dependsOn;
      if (dependsOn != null) {
        final SyncQueueEntry? parent = await (_db.select(
          t,
        )..where((t) => t.id.equals(dependsOn))).getSingleOrNull();

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
    return _countByStatus(<String>['failed', 'blocked']);
  }

  @override
  Future<List<SyncOperation>> recentFailures({int limit = 20}) async {
    final String? ownerId = _currentUserId();
    if (ownerId == null) return const <SyncOperation>[];
    final $SyncQueueTableTable t = _table;

    final List<SyncQueueEntry> entries =
        await (_db.select(t)
              ..where((t) => t.status.isIn(<String>['failed', 'blocked']))
              ..orderBy(<OrderingTerm Function($SyncQueueTableTable)>[
                (t) => OrderingTerm.desc(t.updatedAt),
              ])
              ..limit(limit))
            .get();

    final List<SyncOperation> failures = <SyncOperation>[];
    for (final SyncQueueEntry entry in entries) {
      final QueryRow? scope = await _scope(entry.id);
      if (scope?.read<String?>('owner_user_id') != ownerId) continue;
      final SyncOperation? operation = _safeToOperation(
        entry,
        ownerUserId: ownerId,
        jobId: scope?.read<String?>('job_id'),
      );
      if (operation != null) failures.add(operation);
    }
    return failures;
  }

  @override
  Future<bool> claimPending(String operationId) async {
    final String? ownerId = _currentUserId();
    if (ownerId == null || ownerId.isEmpty) return false;

    // Conditional write: only the caller that finds the row still `pending`
    // flips it, so exactly one concurrent run can win the claim.
    final DateTime now = _now();
    final int affected = await _db.customUpdate(
      '''UPDATE sync_queue
         SET status = ?, last_attempt_at = ?, updated_at = ?
         WHERE id = ? AND status = ?
           AND EXISTS (SELECT 1 FROM sync_operation_scope s
                       WHERE s.operation_id = sync_queue.id AND s.owner_user_id = ?)
           AND (NOT EXISTS (SELECT 1 FROM sync_operation_scope s
                            WHERE s.operation_id = sync_queue.id AND s.job_id IS NOT NULL)
                OR EXISTS (SELECT 1 FROM sync_operation_scope s
                           JOIN local_job_retention r ON r.job_id = s.job_id
                           WHERE s.operation_id = sync_queue.id
                             AND r.retention_state = 'active'
                             AND (r.expires_at IS NULL OR r.expires_at > ?)
                             AND (r.authorized_sync_user_id IS NULL OR r.authorized_sync_user_id = ?)))''',
      variables: <Variable<Object>>[
        Variable<String>(SyncOperationStatus.inProgress.name),
        Variable<DateTime>(now),
        Variable<DateTime>(now),
        Variable<String>(operationId),
        Variable<String>(SyncOperationStatus.pending.name),
        Variable<String>(ownerId),
        Variable<String>(_now().toUtc().toIso8601String()),
        Variable<String>(ownerId),
      ],
      updates: <TableInfo<Table, Object?>>{_table},
    );

    return affected > 0;
  }

  @override
  Future<void> releaseInFlight(String operationId) async {
    final $SyncQueueTableTable t = _table;

    await (_db.update(t)..where(
          (t) =>
              t.id.equals(operationId) &
              t.status.equals(SyncOperationStatus.inProgress.name),
        ))
        .write(
          SyncQueueTableCompanion(
            status: Value(SyncOperationStatus.pending.name),
            updatedAt: Value(_now()),
          ),
        );
  }

  @override
  Future<int> recoverInFlight() async {
    final $SyncQueueTableTable t = _table;

    final int recovered =
        await (_db.update(t)..where(
              (t) => t.status.equals(SyncOperationStatus.inProgress.name),
            ))
            .write(
              SyncQueueTableCompanion(
                status: Value(SyncOperationStatus.pending.name),
                updatedAt: Value(_now()),
              ),
            );

    return recovered;
  }

  @override
  Future<void> requeueFailed() async {
    final String? ownerId = _currentUserId();
    if (ownerId == null || ownerId.isEmpty) return;
    await _db.customUpdate(
      '''UPDATE sync_queue SET status=?, updated_at=?
         WHERE status=? AND (last_error IS NULL OR last_error NOT LIKE 'terminal:%')
           AND EXISTS (SELECT 1 FROM sync_operation_scope s
                       WHERE s.operation_id=sync_queue.id AND s.owner_user_id=?)''',
      variables: <Variable<Object>>[
        Variable<String>(SyncOperationStatus.pending.name),
        Variable<DateTime>(_now()),
        Variable<String>(SyncOperationStatus.failed.name),
        Variable<String>(ownerId),
      ],
      updates: <TableInfo<Table, Object?>>{_table},
    );
  }

  @override
  Future<SyncOperation?> getOperation(String operationId) async {
    final SyncQueueEntry? entry = await (_db.select(
      _table,
    )..where((t) => t.id.equals(operationId))).getSingleOrNull();
    if (entry == null) return null;
    final QueryRow? scope = await _scope(entry.id);
    return _safeToOperation(
      entry,
      ownerUserId: scope?.read<String?>('owner_user_id'),
      jobId: scope?.read<String?>('job_id'),
    );
  }

  @override
  Future<void> recordRemoteJob({
    required String jobId,
    required DateTime createdAt,
  }) async {
    final DateTime utc = createdAt.toUtc();
    await _db.customStatement(
      '''INSERT OR IGNORE INTO local_job_retention
        (job_id, original_created_at, created_at_source, identity_state,
         task_state, expires_at, retention_state, cleanup_step, updated_at)
        VALUES (?, ?, 'server_confirmed', 'owner_unknown', 'server_synced', ?,
                'active', 'not_started', ?)''',
      <Object?>[
        jobId,
        utc.toIso8601String(),
        _oneCalendarYearLater(utc).toIso8601String(),
        _now().toUtc().toIso8601String(),
      ],
    );
  }

  @override
  Future<void> recordRemoteJobs(
    Iterable<MapEntry<String, DateTime>> jobs,
  ) async {
    final List<MapEntry<String, DateTime>> entries = jobs.toList(
      growable: false,
    );
    if (entries.isEmpty) return;
    await _db.transaction(() async {
      for (final MapEntry<String, DateTime> job in entries) {
        await recordRemoteJob(jobId: job.key, createdAt: job.value);
      }
    });
  }

  @override
  Future<void> markSynced(String operationId) async {
    final $SyncQueueTableTable t = _table;
    await _db.transaction(() async {
      final SyncQueueEntry? entry = await (_db.select(
        t,
      )..where((t) => t.id.equals(operationId))).getSingleOrNull();
      if (entry == null) return;
      await (_db.update(t)..where((t) => t.id.equals(operationId))).write(
        SyncQueueTableCompanion(
          status: Value(SyncOperationStatus.synced.name),
          updatedAt: Value(_now()),
        ),
      );
      if (entry.entityType == SyncEntityType.job.name &&
          entry.operation == SyncOperationType.create.name) {
        await _db.customStatement(
          '''UPDATE local_job_retention SET task_state='server_synced', updated_at=?
             WHERE job_id=? AND retention_state='active' ''',
          <Object?>[_now().toUtc().toIso8601String(), entry.entityId],
        );
      }
    });
  }

  @override
  Future<void> markFailed(
    String operationId, {
    required String errorMessage,
  }) async {
    final $SyncQueueTableTable t = _table;

    final SyncQueueEntry? entry = await (_db.select(
      t,
    )..where((t) => t.id.equals(operationId))).getSingleOrNull();

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
  Future<void> markTerminal(
    String operationId, {
    required String safeReason,
  }) async {
    final SyncQueueEntry? entry = await (_db.select(
      _table,
    )..where((t) => t.id.equals(operationId))).getSingleOrNull();
    if (entry == null) return;
    final QueryRow? scope = await _scope(operationId);
    final String? jobId = scope?.read<String?>('job_id');
    final DateTime now = _now();
    if (jobId != null) {
      // A server-confirmed expired/deleted job invalidates its queued updates
      // and file uploads too. Keep every payload, but stop all retries.
      await _db.customUpdate(
        '''UPDATE sync_queue SET status = 'blocked',
           attempt_count = attempt_count + 1, last_attempt_at = ?,
           last_error = ?, updated_at = ?
           WHERE id IN (SELECT operation_id FROM sync_operation_scope WHERE job_id = ?)
             AND status IN ('pending','inProgress','failed')''',
        variables: <Variable<Object>>[
          Variable<DateTime>(now),
          Variable<String>('terminal:$safeReason'),
          Variable<DateTime>(now),
          Variable<String>(jobId),
        ],
        updates: <TableInfo<Table, Object?>>{_table},
      );
    } else {
      await (_db.update(_table)..where((t) => t.id.equals(operationId))).write(
        SyncQueueTableCompanion(
          status: const Value('blocked'),
          attemptCount: Value(entry.attemptCount + 1),
          lastAttemptAt: Value(now),
          lastError: Value('terminal:$safeReason'),
          updatedAt: Value(now),
        ),
      );
    }
  }

  @override
  Future<Set<String>> unfinishedEntityIds(SyncEntityType type) async {
    final String? ownerId = _currentUserId();
    if (ownerId == null) return <String>{};
    final $SyncQueueTableTable t = _table;

    final List<SyncQueueEntry> entries =
        await (_db.select(t)..where(
              (t) =>
                  t.entityType.equals(type.name) &
                  t.status.isIn(<String>[
                    SyncOperationStatus.pending.name,
                    SyncOperationStatus.inProgress.name,
                    SyncOperationStatus.failed.name,
                  'blocked',
                  ]),
            ))
            .get();

    final Set<String> result = <String>{};
    for (final SyncQueueEntry entry in entries) {
      final QueryRow? scope = await _scope(entry.id);
      if (scope?.read<String?>('owner_user_id') == ownerId) {
        result.add(entry.entityId);
      }
    }
    return result;
  }

  // --- Internals ---------------------------------------------------------------

  Future<int> _countByStatus(List<String> statuses) async {
    final String? ownerId = _currentUserId();
    if (ownerId == null || ownerId.isEmpty) return 0;
    final List<String> placeholders = List.filled(statuses.length, '?');
    final QueryRow row = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM sync_queue '
          'WHERE status IN (${placeholders.join(', ')}) '
          'AND EXISTS (SELECT 1 FROM sync_operation_scope s '
          'WHERE s.operation_id=sync_queue.id AND s.owner_user_id=?)',
          variables: <Variable<Object>>[
            ...statuses.map(Variable<Object>.new),
            Variable<String>(ownerId),
          ],
        )
        .getSingle();

    return row.read<int>('c');
  }

  /// Maps a row to a [SyncOperation]; returns `null` (with a warning) for rows
  /// whose enums no longer exist, so one corrupt row can never wedge the queue.
  SyncOperation? _safeToOperation(
    SyncQueueEntry entry, {
    String? ownerUserId,
    String? jobId,
  }) {
    try {
      return _toOperation(entry, ownerUserId: ownerUserId, jobId: jobId);
    } catch (error) {
      AppLogger.warning(
        'Sync queue: skipping unparseable row ${entry.id}.',
        error: error,
      );
      return null;
    }
  }

  SyncOperation _toOperation(
    SyncQueueEntry entry, {
    String? ownerUserId,
    String? jobId,
  }) {
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
      ownerUserId: ownerUserId,
      jobId: jobId,
    );
  }

  String? _jobIdFor(SyncOperation operation) {
    if (operation.entityType == SyncEntityType.job) return operation.entityId;
    if (operation.entityType == SyncEntityType.jobFile) {
      final Object? value = operation.payload['jobId'];
      return value is String && value.isNotEmpty ? value : null;
    }
    return null;
  }

  DateTime? _creationTime(SyncOperation operation) {
    final Object? value = operation.payload['created_at'];
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    if (operation.entityType == SyncEntityType.job &&
        operation.type == SyncOperationType.create) {
      // Only the explicit create operation's timestamp has this meaning in
      // the prior queue contract. Update/upload timestamps are never used.
      return operation.createdAt.toUtc();
    }
    return null;
  }

  String _creationTimeSource(SyncOperation operation) {
    final Object? value = operation.payload['created_at'];
    return value is String && DateTime.tryParse(value) != null
        ? 'device_clock'
        : 'queue_operation_created_at';
  }

  DateTime _oneCalendarYearLater(DateTime value) {
    final int year = value.year + 1;
    final int day = value.day.clamp(1, DateTime.utc(year, value.month + 1, 0).day);
    return DateTime.utc(year, value.month, day, value.hour, value.minute,
        value.second, value.millisecond, value.microsecond);
  }

  Future<QueryRow?> _scope(String operationId) => _db.customSelect(
    'SELECT owner_user_id, job_id FROM sync_operation_scope WHERE operation_id = ?',
    variables: <Variable<Object>>[Variable<String>(operationId)],
  ).getSingleOrNull();

  Future<QueryRow?> _retention(String jobId) => _db.customSelect(
    'SELECT retention_state, authorized_sync_user_id, expires_at '
    'FROM local_job_retention WHERE job_id = ?',
    variables: <Variable<Object>>[Variable<String>(jobId)],
  ).getSingleOrNull();

  Future<void> _blockExpiredJob(String jobId) async {
    final DateTime now = _now();
    await _db.transaction(() async {
      await _db.customStatement(
        '''UPDATE local_job_retention SET retention_state='expired_pending_cleanup',
           cleanup_step='awaiting_cleanup', updated_at=?
           WHERE job_id=? AND retention_state='active' ''',
        <Object?>[now.toUtc().toIso8601String(), jobId],
      );
      await _db.customUpdate(
        '''UPDATE sync_queue SET status='blocked', attempt_count=attempt_count+1,
           last_attempt_at=?, last_error='terminal:local_retention_elapsed', updated_at=?
           WHERE id IN (SELECT operation_id FROM sync_operation_scope WHERE job_id=?)
             AND status IN ('pending','inProgress','failed')''',
        variables: <Variable<Object>>[
          Variable<DateTime>(now),
          Variable<DateTime>(now),
          Variable<String>(jobId),
        ],
        updates: <TableInfo<Table, Object?>>{_table},
      );
    });
  }
}
