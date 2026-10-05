import 'package:drift/drift.dart';
import 'package:field_service/core/database/app_database.dart';
import 'package:field_service/features/customers/data/models/customer_model.dart';
import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/customers/domain/entities/customer_sync_status.dart';

/// Local (Drift/SQLite) persistence for customers — the offline-first source
/// of truth for the UI.
///
/// Contains no business rules beyond persistence mechanics: queueing stays
/// in the repository, pushing stays in the sync handler.
abstract interface class CustomersLocalDataSource {
  /// All customers, name first; re-emits on every local write and on every
  /// merged pull.
  Stream<List<Customer>> watchAll();

  /// One customer, live (`null` when it does not exist or was deleted).
  Stream<Customer?> watchById(String id);

  /// One customer, once.
  Future<Customer?> getById(String id);

  /// Inserts [model] verbatim (its [CustomerModel.syncStatus] decides
  /// whether the fresh row is `pending` or `synced`).
  Future<Customer> insert(CustomerModel model);

  /// Overwrites the mutable columns of the existing row with [model] and
  /// marks it `pending` + `localUpdatedAt` — an edit is by definition an
  /// unsynchronized local change. Returns the saved row.
  Future<Customer> update(CustomerModel model);

  /// Removes the row (the queued `delete` operation travels with it).
  Future<void> deleteLocally(String id);

  /// Moves one row's sync metadata (`pending`/`inProgress`/`failed`/
  /// `synced`) — called by the sync handler around each push attempt.
  /// Missing rows are a no-op (e.g. a create push that resolves after the
  /// customer was deleted again).
  Future<void> markSyncStatus(
    String id,
    CustomerSyncStatus status, {
    DateTime? syncedAt,
  });

  /// Merges pulled [rows] into the mirror, atomically:
  /// * unknown ids are inserted as `synced`;
  /// * known ids **not** in [protectedEntityIds] are overwritten with the
  ///   remote values and marked `synced`;
  /// * [protectedEntityIds] (entities with unfinished queue operations,
  ///   including pending deletes) are skipped entirely — a pull never
  ///   clobbers local pending work and never resurrects a locally deleted
  ///   record whose delete has not been pushed yet.
  Future<void> mergeRemoteRows(
    List<CustomerModel> rows, {
    required Set<String> protectedEntityIds,
    required DateTime pulledAt,
  });

  /// Rows of the local `jobs` mirror referencing this customer
  /// (`jobs.customer_id`). The FK on the backend stays authoritative — this
  /// is the friendly local guard.
  Future<int> countJobsReferencing(String customerId);
}

class DriftCustomersLocalDataSource implements CustomersLocalDataSource {
  const DriftCustomersLocalDataSource(this._db);

  final AppDatabase _db;

  $CustomersTableTable get _table => _db.customersTable;

  @override
  Stream<List<Customer>> watchAll() {
    final $CustomersTableTable t = _table;
    return (_db.select(t)
          ..orderBy(<OrderingTerm Function($CustomersTableTable)>[
            (t) => OrderingTerm.asc(t.name),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .watch()
        .map((List<LocalCustomer> rows) =>
            rows.map(CustomerModel.fromLocalRow).toList());
  }

  @override
  Stream<Customer?> watchById(String id) {
    final $CustomersTableTable t = _table;
    return (_db.select(t)..where((t) => t.id.equals(id)))
        .watch()
        .map((List<LocalCustomer> rows) =>
            rows.isEmpty ? null : CustomerModel.fromLocalRow(rows.first));
  }

  @override
  Future<Customer?> getById(String id) async {
    final LocalCustomer? row = await (
      _db.select(_table)..where((t) => t.id.equals(id))
    ).getSingleOrNull();

    return row == null ? null : CustomerModel.fromLocalRow(row);
  }

  @override
  Future<Customer> insert(CustomerModel model) async {
    await _db.into(_table).insert(model.toLocalCompanion(isNew: true));
    return model;
  }

  @override
  Future<Customer> update(CustomerModel model) async {
    final DateTime now = DateTime.now();
    final CustomerModel pending = model.copyWithSyncStatus(
      CustomerSyncStatus.pending,
    );

    await (_db.update(_table)..where((t) => t.id.equals(model.id))).write(
      CustomersTableCompanion(
        name: Value(pending.name),
        phone: Value(pending.phone),
        email: Value(pending.email),
        address: Value(pending.address),
        city: Value(pending.city),
        postalCode: Value(pending.postalCode),
        notes: Value(pending.notes),
        updatedAt: Value(pending.updatedAt),
        syncStatus: Value(pending.syncStatus.name),
        localUpdatedAt: Value(now),
      ),
    );

    return pending;
  }

  @override
  Future<void> deleteLocally(String id) async {
    await (_db.delete(_table)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<void> markSyncStatus(
    String id,
    CustomerSyncStatus status, {
    DateTime? syncedAt,
  }) {
    return (_db.update(_table)..where((t) => t.id.equals(id))).write(
      CustomersTableCompanion(
        syncStatus: Value(status.name),
        lastSyncedAt: syncedAt == null
            ? const Value.absent()
            : Value(syncedAt),
      ),
    );
  }

  @override
  Future<void> mergeRemoteRows(
    List<CustomerModel> rows, {
    required Set<String> protectedEntityIds,
    required DateTime pulledAt,
  }) {
    return _db.transaction(() async {
      for (final CustomerModel row in rows) {
        if (protectedEntityIds.contains(row.id)) {
          continue;
        }

        await _db
            .into(_table)
            .insertOnConflictUpdate(
              CustomersTableCompanion(
                id: Value(row.id),
                name: Value(row.name),
                phone: Value(row.phone),
                email: Value(row.email),
                address: Value(row.address),
                city: Value(row.city),
                postalCode: Value(row.postalCode),
                notes: Value(row.notes),
                createdAt: Value(row.createdAt),
                updatedAt: Value(row.updatedAt),
                syncStatus: const Value('synced'),
                localUpdatedAt: const Value(null),
                lastSyncedAt: Value(pulledAt),
              ),
            );
      }
    });
  }

  @override
  Future<int> countJobsReferencing(String customerId) async {
    // Aggregated count over the local jobs mirror (same custom-query style as
    // `DriftSyncQueue._countByStatus`). It reads only the schema the tables
    // folder owns — no dependency on the Jobs feature's code.
    final QueryRow row = await _db.customSelect(
      'SELECT COUNT(*) AS c FROM jobs WHERE customer_id = ?',
      variables: <Variable<Object>>[Variable.withString(customerId)],
    ).getSingle();

    return row.read<int>('c');
  }
}
