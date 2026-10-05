import 'package:drift/drift.dart';

/// Local mirror of the `customers` table.
///
/// The first three groups of columns map 1:1 to the existing Supabase table
/// (`customers`); the trailing `syncStatus` / `localUpdatedAt` /
/// `lastSyncedAt` columns are **local-only synchronization metadata** — they
/// never exist on the backend and never leave the device. Keeping them local
/// (instead of on the Supabase tables) is a deliberate architectural rule:
/// the remote schema stays untouched.
@DataClassName('LocalCustomer')
class CustomersTable extends Table {
  @override
  String get tableName => 'customers';

  // --- Mirror of the remote schema ------------------------------------------
  TextColumn get id => text()();

  TextColumn get name => text()();

  TextColumn get phone => text().nullable()();

  TextColumn get email => text().nullable()();

  TextColumn get address => text()();

  TextColumn get city => text().nullable()();

  TextColumn get postalCode => text().nullable()();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  // --- Local-only sync metadata ---------------------------------------------

  /// `pending` = local change not yet pushed, `inProgress`, `synced`,
  /// `failed`. Rows created by a future remote pull start as `synced`; local
  /// edits flip them to `pending`.
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();

  /// When the row was last modified locally.
  DateTimeColumn get localUpdatedAt => dateTime().nullable()();

  /// When the row last reached (or came from) the backend.
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
