import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:field_service/core/database/app_database.dart';
import 'package:field_service/core/storage/file_storage.dart';

/// Resumable, job-scoped local cleanup. It is deliberately not scheduled by
/// this change: run it only after staging validation and owner approval.
class LocalJobRetentionCleaner {
  LocalJobRetentionCleaner({
    required AppDatabase database,
    required FileStorage fileStorage,
    required String? Function() currentUserId,
    DateTime Function()? now,
  }) : _db = database,
       _fileStorage = fileStorage,
       _currentUserId = currentUserId,
       _now = now ?? DateTime.now;

  final AppDatabase _db;
  final FileStorage _fileStorage;
  final String? Function() _currentUserId;
  final DateTime Function() _now;

  Future<int> sweep() async {
    final String? ownerId = _currentUserId();
    if (ownerId == null || ownerId.isEmpty) return 0;
    final String now = _now().toUtc().toIso8601String();
    final List<QueryRow> due = await _db.customSelect(
      '''SELECT job_id FROM local_job_retention
         WHERE identity_state = 'verified'
           AND authorized_sync_user_id IS NOT NULL
           AND authorized_sync_user_id = ?
           AND expires_at IS NOT NULL AND expires_at <= ?
           AND retention_state IN ('active', 'expired_pending_cleanup', 'cleaning', 'cleanup_failed')
         ORDER BY expires_at, job_id''',
      variables: <Variable<Object>>[
        Variable<String>(ownerId),
        Variable<String>(now),
      ],
    ).get();

    int completed = 0;
    for (final QueryRow row in due) {
      if (await _cleanJob(row.read<String>('job_id'))) completed++;
    }
    return completed;
  }

  Future<bool> _cleanJob(String jobId) async {
    final String? ownerId = _currentUserId();
    if (ownerId == null || ownerId.isEmpty) return false;
    // Mark first: the sync queue filters any operation for a job whose
    // retention state is no longer active.
    final int eligible = await _db.customUpdate(
      '''UPDATE local_job_retention
         SET retention_state = 'cleaning', cleanup_step = 'files',
             last_cleanup_error = NULL, updated_at = ?
         WHERE job_id = ? AND identity_state = 'verified'
           AND authorized_sync_user_id = ? AND expires_at <= ?''',
      variables: <Variable<Object>>[
        Variable<String>(_now().toUtc().toIso8601String()),
        Variable<String>(jobId),
        Variable<String>(ownerId),
        Variable<String>(_now().toUtc().toIso8601String()),
      ],
      updates: const <TableInfo<Table, Object?>>{},
    );
    if (eligible == 0) return false;

    final List<QueryRow> files = await _db.customSelect(
      'SELECT id, local_path FROM job_files WHERE job_id = ? ORDER BY id',
      variables: <Variable<Object>>[Variable<String>(jobId)],
    ).get();
    final Set<String> fileIds = <String>{};
    for (final QueryRow file in files) {
      fileIds.add(file.read<String>('id'));
    }

    final List<QueryRow> queueRows = await _db.customSelect(
      '''SELECT q.id FROM sync_queue q
         LEFT JOIN sync_operation_scope s ON s.operation_id = q.id
         WHERE s.job_id = ? OR (q.entity_type = 'job' AND q.entity_id = ?)''',
      variables: <Variable<Object>>[Variable<String>(jobId), Variable<String>(jobId)],
    ).get();
    final Set<String> operationIds = queueRows.map((r) => r.read<String>('id')).toSet();
    // Include legacy file-upload rows by their explicit payload relationship;
    // never infer task ownership from the current account.
    final List<QueryRow> uploads = await _db.customSelect(
      "SELECT id, entity_id, payload FROM sync_queue WHERE entity_type = 'jobFile'",
    ).get();
    bool hasUnregisteredUpload = false;
    for (final QueryRow row in uploads) {
      if (fileIds.contains(row.read<String>('entity_id'))) {
        operationIds.add(row.read<String>('id'));
        continue;
      }
      try {
        final Object? payload = jsonDecode(row.read<String>('payload'));
        if (payload is Map && payload['jobId'] == jobId) {
          operationIds.add(row.read<String>('id'));
          // Without the file metadata row there is no proved ownership of the
          // local path; retain the entire cleanup scope for manual recovery.
          hasUnregisteredUpload = true;
        }
      } catch (_) {
        // An unreadable legacy payload is not guessed or deleted.
      }
    }
    if (hasUnregisteredUpload) {
      await _recordFailure(jobId, 'unregistered_local_upload');
      return false;
    }
    if (operationIds.isNotEmpty) {
      final List<String> ids = operationIds.toList();
      final String placeholders = List<String>.filled(ids.length, '?').join(',');
      final QueryRow owners = await _db.customSelect(
        '''SELECT COUNT(*) AS c FROM sync_queue q
           LEFT JOIN sync_operation_scope s ON s.operation_id=q.id
           WHERE q.id IN ($placeholders)
             AND (s.owner_user_id IS NULL OR s.owner_user_id <> ?)''',
        variables: <Variable<Object>>[
          ...ids.map(Variable<Object>.new),
          Variable<String>(ownerId),
        ],
      ).getSingle();
      if (owners.read<int>('c') > 0) {
        await _recordFailure(jobId, 'operation_owner_unverified');
        return false;
      }
      final QueryRow inFlight = await _db.customSelect(
        '''SELECT COUNT(*) AS c FROM sync_queue
           WHERE id IN ($placeholders) AND status='inProgress' ''',
        variables: ids.map(Variable<Object>.new).toList(),
      ).getSingle();
      if (inFlight.read<int>('c') > 0) {
        await _recordFailure(jobId, 'sync_operation_in_flight');
        return false;
      }
    }
    if (operationIds.isNotEmpty) {
      final List<String> ids = operationIds.toList();
      final String placeholders = List<String>.filled(ids.length, '?').join(',');
      final QueryRow dependents = await _db.customSelect(
        '''SELECT COUNT(*) AS c FROM sync_queue child
           WHERE child.depends_on IN ($placeholders)
             AND child.id NOT IN ($placeholders)''',
        variables: <Variable<Object>>[
          for (final String id in ids) Variable<String>(id),
          for (final String id in ids) Variable<String>(id),
        ],
      ).getSingle();
      if (dependents.read<int>('c') > 0) {
        await _recordFailure(jobId, 'external_sync_dependency');
        return false;
      }
    }

    // Only begin deleting local bytes after confirming there are no operations
    // from another entity depending on this job's operations.
    try {
      for (final QueryRow file in files) {
        if (_currentUserId() != ownerId) {
          await _recordFailure(jobId, 'account_changed_during_cleanup');
          return false;
        }
        final String fileId = file.read<String>('id');
        await _fileStorage.delete(file.read<String>('local_path'));
        await _db.customUpdate(
          'DELETE FROM job_files WHERE id = ? AND job_id = ?',
          variables: <Variable<Object>>[
            Variable<String>(fileId),
            Variable<String>(jobId),
          ],
        );
      }
    } catch (_) {
      await _recordFailure(jobId, 'local_file_delete_failed');
      return false;
    }

    try {
      await _db.transaction(() async {
        if (_currentUserId() != ownerId) {
          throw StateError('Account changed during local retention cleanup.');
        }
        if (operationIds.isNotEmpty) {
          final List<String> ids = operationIds.toList();
          final String placeholders = List<String>.filled(ids.length, '?').join(',');
          await _db.customStatement(
            'UPDATE sync_queue SET depends_on = NULL WHERE id IN ($placeholders)', ids,
          );
          await _db.customStatement(
            'DELETE FROM sync_queue WHERE id IN ($placeholders)', ids,
          );
        }
        await _db.customStatement('DELETE FROM job_events WHERE job_id = ?', <Object?>[jobId]);
        await _db.customStatement('DELETE FROM jobs WHERE id = ?', <Object?>[jobId]);
        // Keep only a minimal anti-resurrection tombstone. It contains no task,
        // customer or account data and is needed to reject a stale local retry.
        await _db.customStatement(
          '''UPDATE local_job_retention SET original_created_at = NULL,
             created_at_source = 'purged', created_by_user_id = NULL,
             authorized_sync_user_id = NULL, identity_state = 'purged',
             task_state = 'deleted', expires_at = NULL,
             retention_state = 'purged', cleanup_step = 'complete',
             last_cleanup_error = NULL, updated_at = ? WHERE job_id = ?''',
          <Object?>[_now().toUtc().toIso8601String(), jobId],
        );
      });
    } catch (_) {
      await _recordFailure(jobId, 'local_cleanup_commit_failed');
      return false;
    }
    return true;
  }

  Future<void> _recordFailure(String jobId, String reason) => _db.customStatement(
    '''UPDATE local_job_retention SET retention_state = 'cleanup_failed',
       cleanup_step = ?, last_cleanup_error = ?, updated_at = ? WHERE job_id = ?''',
    <Object?>[reason, reason, _now().toUtc().toIso8601String(), jobId],
  );
}
