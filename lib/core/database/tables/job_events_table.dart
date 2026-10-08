import 'package:drift/drift.dart';

/// Local mirror of the append-only `job_events` table.
///
/// The remote table's exact event columns are intentionally not hard-coded
/// here: an event is modelled as (type + JSON payload), which keeps the local
/// schema stable while the event catalogue grows. Event-specific data lives
/// in [payload]; the columns that matter for every event (id, job, type,
/// time) are first-class.
///
/// Append-only: no code path in this phase updates or deletes an event row.
/// Deleting the parent job cascades to its events.
@DataClassName('LocalJobEvent')
class JobEventsTable extends Table {
  @override
  String get tableName => 'job_events';

  // --- Event identity ---------------------------------------------------------
  TextColumn get id => text()();

  /// `job_events.job_id` (FK → `jobs.id`).
  TextColumn get jobId => text()();

  /// Which event this is (`job_created`, `job_started`, `note_added`, ...).
  TextColumn get eventType => text()();

  /// JSON payload with the event-specific data.
  TextColumn get payload => text()();

  DateTimeColumn get createdAt => dateTime()();

  // --- Local-only sync metadata -----------------------------------------------
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();

  DateTimeColumn get localUpdatedAt => dateTime().nullable()();

  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => <String>[
    'CONSTRAINT fk_job_events_job FOREIGN KEY (job_id) '
        'REFERENCES jobs (id) ON DELETE CASCADE',
  ];
}
