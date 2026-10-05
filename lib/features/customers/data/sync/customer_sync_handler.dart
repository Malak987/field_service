import 'package:field_service/core/sync/sync_handler.dart';
import 'package:field_service/core/sync/sync_operation.dart';
import 'package:field_service/features/customers/data/datasources/customers_local_data_source.dart';
import 'package:field_service/features/customers/data/datasources/customers_remote_data_source.dart';
import 'package:field_service/features/customers/domain/entities/customer_sync_status.dart';

/// Pushes queued `customer` operations to Supabase.
///
/// Registered in the shared [SyncHandlerRegistry] by the customers DI module —
/// this is *the* existing mechanism for a feature to join the sync system,
/// not a second one. Ordering, claims and queue-state transitions stay with
/// the [SyncManager]; this class only performs the remote write and mirrors
/// the outcome onto the local row's sync metadata so the UI chip can show
/// `pending → syncing → synced / failed` per record.
///
/// Guarantees:
/// * **Idempotent.** Every payload carries the stable client-generated UUID
///   as `id`. A create is an `upsert(onConflict: 'id')`; retrying the same
///   operation can therefore never duplicate a customer.
/// * **Retry-safe.** Expected remote failures are *not* swallowed: the row is
///   marked `failed`, the exception is rethrown, and the [SyncManager]
///   persists the queue row as `failed` with a sanitised reason — the
///   operation stays in the queue and becomes retryable
///   (`retryFailedOperations` / next connectivity event).
/// * **No resurrection surprises.** A delete that the backend already applied
///   (row missing) counts as success; an *update* to a missing row is a
///   genuine conflict and stays failed rather than silently recreating data.
class CustomerSyncHandler implements SyncOperationHandler {
  CustomerSyncHandler({
    required this._remote,
    required this._local,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final CustomersRemoteDataSource _remote;
  final CustomersLocalDataSource _local;
  final DateTime Function() _now;

  @override
  Future<RemotePushResult> push(SyncOperation operation) async {
    if (operation.entityType != SyncEntityType.customer) {
      return RemotePushResult.failure(
        'CustomerSyncHandler received a "${operation.entityType.name}" '
        'operation.',
      );
    }

    final String customerId = operation.entityId;
    final Map<String, Object?> payload = operation.payload;

    try {
      switch (operation.type) {
        case SyncOperationType.create:
          // Upsert on the stable id: replay-safe, never a duplicate.
          await _remote.upsertRow(payload);
          await _local.markSyncStatus(
            customerId,
            CustomerSyncStatus.synced,
            syncedAt: _now(),
          );
          return const RemotePushResult.ok();

        case SyncOperationType.update:
          final bool applied = await _remote.updateRow(
            id: customerId,
            changes: _updateChanges(payload),
          );
          if (!applied) {
            await _local.markSyncStatus(customerId, CustomerSyncStatus.failed);
            return const RemotePushResult.failure(
              'The customer no longer exists on the backend; the update was '
              'not applied.',
            );
          }
          await _local.markSyncStatus(
            customerId,
            CustomerSyncStatus.synced,
            syncedAt: _now(),
          );
          return const RemotePushResult.ok();

        case SyncOperationType.delete:
          // Missing remotely == already deleted == success (idempotent).
          await _remote.deleteRow(customerId);
          return const RemotePushResult.ok();

        case SyncOperationType.upload:
          // Uploads belong to job files, never to customer records.
          return const RemotePushResult.failure(
            'Customer records cannot carry an upload operation.',
          );
      }
    } catch (error) {
      // Surface the attempt on the row for the per-customer badge, then let
      // the manager translate + persist the queue-side failure. Never mark
      // the row `synced` on a failed push.
      await _markFailedQuietly(customerId);
      rethrow;
    }
  }

  /// Everything mutable in an update; `id` is the selector and `created_at`
  /// is server-owned. Kept as a subtraction of [payload] so the payload
  /// schema has one owner ([CustomerModel.toRemoteRow]).
  static Map<String, Object?> _updateChanges(Map<String, Object?> payload) {
    return Map<String, Object?>.from(payload)
      ..remove('id')
      ..remove('created_at');
  }

  Future<void> _markFailedQuietly(String customerId) async {
    try {
      await _local.markSyncStatus(customerId, CustomerSyncStatus.failed);
    } catch (_) {
      // The queue-side failure is what matters; never mask the original
      // error with a bookkeeping one.
    }
  }
}
