import 'package:drift/drift.dart';

/// Local mirror of the `jobs` table.
///
/// Columns map 1:1 to the verified remote schema (no invented columns);
/// `customerId` / `assignedEmployeeId` are the real foreign keys, stored as
/// plain ids (the remote resolves them, the local app does not join to local
/// employees). The trailing `syncStatus` / `localUpdatedAt` /
/// `lastSyncedAt` columns are local-only synchronization metadata.
@DataClassName('LocalJob')
class JobsTable extends Table {
  @override
  String get tableName => 'jobs';

  // --- Mirror of the remote schema ------------------------------------------
  TextColumn get id => text()();

  /// `jobs.job_number` (bigint).
  Int64Column get jobNumber => int64()();

  /// `jobs.customer_id` (FK → `customers.id`).
  TextColumn get customerId => text()();

  /// `jobs.assigned_employee_id` (FK → `employees.id`), nullable.
  TextColumn get assignedEmployeeId => text().nullable()();

  /// Free text — the backend does not constrain it.
  TextColumn get jobType => text()();

  TextColumn get description => text().nullable()();

  /// Free text (default `assigned` on the backend).
  TextColumn get status => text()();

  DateTimeColumn get assignedAt => dateTime().nullable()();

  DateTimeColumn get startedAt => dateTime().nullable()();

  DateTimeColumn get completedAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  DateTimeColumn get expiresAt => dateTime()();

  // --- Local-only sync metadata ---------------------------------------------
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();

  DateTimeColumn get localUpdatedAt => dateTime().nullable()();

  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
