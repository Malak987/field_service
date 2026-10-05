import 'package:drift/drift.dart';

/// Local table of queued changes waiting to reach the backend.
///
/// One row = one logical change (create/update/delete/upload of one entity).
/// The queue is the durable backbone of the offline-first flow: it survives
/// restarts, force closes and airplane mode, and it is what makes "write
/// locally, sync later" safe.
///
/// All state is stored as plain strings (no SQLite enums) so the sync layer
/// stays extensible: new entity types or operations can be added without a
/// destructive schema change.
@DataClassName('SyncQueueEntry')
class SyncQueueTable extends Table {
  @override
  String get tableName => 'sync_queue';

  /// Operation id — client generated (uuid). Stable across retries, which is
  /// what makes idempotent re-enqueue and duplicate detection possible.
  TextColumn get id => text()();

  /// Which aggregate this change belongs to (`customer`, `job`, `job_event`,
  /// `job_file`, ...).
  TextColumn get entityType => text()();

  /// The affected entity's id (client generated, see [SyncQueueTable.id]).
  TextColumn get entityId => text()();

  /// What happened (`create`, `update`, `delete`, `upload`).
  TextColumn get operation => text()();

  /// JSON snapshot of the change, ready to be replayed on the backend.
  TextColumn get payload => text()();

  /// Id of another operation that must be `synced` before this one may be
  /// pushed (dependency ordering, e.g. job creation depends on the customer
  /// creation it references). `null` when there is no dependency.
  TextColumn get dependsOn => text().nullable()();

  /// Lifecycle: `pending`, `inProgress`, `synced`, `failed`.
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// How many push attempts have been made; drives retries and the
  /// admin/debug view. Never reset on success — it is history.
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();

  /// When the last attempt was made, if any.
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();

  /// Sanitised error of the last failed attempt (kept for diagnostics; raw
  /// backend exceptions are never stored verbatim).
  TextColumn get lastError => text().nullable()();

  /// When the local change happened (queue ordering key).
  DateTimeColumn get createdAt => dateTime()();

  /// Last status change of this row (audit + ordering of recent failures).
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => <String>[
    // Self reference: a dependency must point at an existing operation.
    // Rows are never deleted in this phase, so this can never block
    // legitimate work; it only protects against corrupt references.
    'CONSTRAINT fk_sync_queue_depends_on FOREIGN KEY (depends_on) '
    'REFERENCES sync_queue (id)',
  ];
}
