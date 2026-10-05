import 'dart:async';

import 'package:field_service/core/network/connectivity_service.dart';
import 'package:field_service/core/sync/sync_operation.dart';
import 'package:field_service/core/sync/sync_processor.dart';
import 'package:field_service/core/sync/sync_queue.dart';
import 'package:field_service/features/customers/data/datasources/customers_local_data_source.dart';
import 'package:field_service/features/customers/data/datasources/customers_remote_data_source.dart';
import 'package:field_service/features/customers/data/models/customer_model.dart';
import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/customers/domain/entities/customer_sync_status.dart';
import 'package:field_service/features/customers/domain/repositories/customers_repository.dart';
import 'package:uuid/uuid.dart';

/// Offline-first [CustomersRepository] implementation.
///
/// Reads come from Drift; writes land in Drift *first* (with stable
/// client-generated UUIDs) and are appended to the durable [SyncQueue]. The
/// shared [SyncProcessor] gets a nudge after every enqueue so an already
/// online device pushes immediately, while an offline one simply queues —
/// this is one engine (the existing `SyncManager`), not a second one.
///
/// Pulling ([refreshFromRemote]) merges remote rows into the mirror but never
/// overwrites rows that still have unfinished queue operations — local
/// pending work always outlives a concurrent remote state.
class CustomersRepositoryImpl implements CustomersRepository {
  CustomersRepositoryImpl({
    required this._local,
    required this._remote,
    required this._syncQueue,
    required this._syncProcessor,
    required this._connectivity,
    Uuid? uuid,
    DateTime Function()? now,
  }) : _uuid = uuid ?? const Uuid(),
       _now = now ?? _utcNow;

  final CustomersLocalDataSource _local;
  final CustomersRemoteDataSource _remote;
  final SyncQueue _syncQueue;
  final SyncProcessor _syncProcessor;
  final ConnectivityService _connectivity;
  final Uuid _uuid;
  final DateTime Function() _now;

  @override
  Stream<List<Customer>> watchCustomers() => _local.watchAll();

  @override
  Stream<Customer?> watchCustomerById(String id) => _local.watchById(id);

  @override
  Future<Customer?> getCustomerById(String id) => _local.getById(id);

  @override
  Future<Customer> createCustomer({
    required String name,
    required String address,
    String? phone,
    String? email,
    String? city,
    String? postalCode,
    String? notes,
  }) async {
    // 1) Stable UUID + timestamps, generated client-side so the record is
    //    fully addressable before the backend ever sees it.
    final DateTime now = _now();
    final CustomerModel model = CustomerModel(
      id: _uuid.v4(),
      name: name.trim(),
      address: address.trim(),
      phone: _trimmedOrNull(phone),
      email: _trimmedOrNull(email),
      city: _trimmedOrNull(city),
      postalCode: _trimmedOrNull(postalCode),
      notes: _trimmedOrNull(notes),
      createdAt: now,
      updatedAt: now,
      syncStatus: CustomerSyncStatus.pending,
    );

    // 2) Save locally, 3) queue the create, 4) nudge the (single) sync run.
    final Customer saved = await _local.insert(model);
    await _enqueue(
      type: SyncOperationType.create,
      payload: model.toRemoteRow(),
    );
    _notifySyncProcessor();

    return saved;
  }

  @override
  Future<void> updateCustomer(Customer customer) async {
    // The stable id is kept; `updated_at` is stamped here so the local row
    // and the queued payload agree on one value (retries never re-stamp).
    final CustomerModel model = CustomerModel(
      id: customer.id,
      name: customer.name.trim(),
      address: customer.address.trim(),
      phone: _trimmedOrNull(customer.phone),
      email: _trimmedOrNull(customer.email),
      city: _trimmedOrNull(customer.city),
      postalCode: _trimmedOrNull(customer.postalCode),
      notes: _trimmedOrNull(customer.notes),
      createdAt: customer.createdAt,
      updatedAt: _now(),
      syncStatus: CustomerSyncStatus.pending,
    );

    await _local.update(model);
    await _enqueue(
      type: SyncOperationType.update,
      payload: model.toRemoteRow(),
    );
    _notifySyncProcessor();
  }

  @override
  Future<void> deleteCustomer(String id) async {
    final int linkedJobs = await _local.countJobsReferencing(id);
    if (linkedJobs > 0) {
      // Deleting now would orphan jobs the device already knows about. The
      // remote FK (jobs.customer_id → customers.id) stays the authoritative
      // backstop for jobs this device has not cached.
      throw CustomerLinkedToJobsException(id, linkedJobs);
    }

    await _local.deleteLocally(id);
    await _enqueue(
      type: SyncOperationType.delete,
      payload: <String, Object?>{'id': id},
    );
    _notifySyncProcessor();
  }

  @override
  Future<void> refreshFromRemote() async {
    // "If online, synchronize remote changes" — offline, the local mirror is
    // already the answer; never fail the UI for a skipped pull.
    if (!_connectivity.isOnline) {
      return;
    }

    // Ask the queue first: rows with unfinished operations (local create not
    // yet pushed, edits pending, deletes awaiting retry) are protected from
    // the merge in both directions.
    final Set<String> protectedIds = await _syncQueue.unfinishedEntityIds(
      SyncEntityType.customer,
    );

    final List<CustomerModel> rows = await _remote.fetchAll();
    await _local.mergeRemoteRows(
      rows,
      protectedEntityIds: protectedIds,
      pulledAt: _now(),
    );
  }

  @override
  Future<int> countLinkedJobs(String id) => _local.countJobsReferencing(id);

  // --- Internals -----------------------------------------------------------------

  /// Appends one operation for this feature to the shared queue.
  ///
  /// FIFO on `createdAt` is what orders create → update → delete for the same
  /// entity; the queue's `dependsOn` mechanism stays reserved for genuine
  /// cross-aggregate dependencies (e.g. a future job referencing a pending
  /// customer).
  Future<void> _enqueue({
    required SyncOperationType type,
    required Map<String, Object?> payload,
  }) {
    final DateTime now = _now();
    return _syncQueue.enqueue(
      SyncOperation(
        id: _uuid.v4(),
        entityType: SyncEntityType.customer,
        entityId: payload['id']! as String,
        type: type,
        payload: payload,
        createdAt: now,
      ),
    );
  }

  /// Fire-and-forget: the manager serialises runs and stops itself without
  /// connectivity, so this is safe offline (it just finds nothing to do).
  void _notifySyncProcessor() {
    unawaited(
      _syncProcessor.processPendingOperations().catchError((Object _) {
        // Sync runs never crash the write path; the operation stays queued.
      }),
    );
  }

  static String? _trimmedOrNull(String? value) {
    final String? trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}

/// Clock with a UTC representation: the instant written to Drift and
/// serialized into the sync payload is then byte-for-byte the same value, so
/// retries, `updated_at` comparisons and tests never depend on the device
/// time zone (a UTC `DateTime` is deliberately *not* `==` to the local one).
DateTime _utcNow() => DateTime.now().toUtc();
