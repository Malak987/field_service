import 'package:drift/drift.dart';

/// Local metadata of files attached to jobs (before/after photos, customer
/// signatures, documents).
///
/// The **bytes** live on disk behind `FileStorage`; this table stores where
/// they are ([localPath], a path relative to the app-owned storage root) and
/// where they will end up once uploaded ([remotePath], filled by the sync
/// engine). One job may have any number of files of any kind — there is no
/// "one before photo" assumption anywhere in the schema.
///
/// [id] is the stable, client-generated file id (uuid): it is known before
/// the backend has ever seen the file, which is what makes retries
/// idempotent.
@DataClassName('LocalJobFile')
class JobFilesTable extends Table {
  @override
  String get tableName => 'job_files';

  // --- File identity -----------------------------------------------------------
  TextColumn get id => text()();

  /// `job_files.job_id` (FK → `jobs.id`).
  TextColumn get jobId => text()();

  /// Path of the local copy, relative to the storage root.
  TextColumn get localPath => text()();

  /// Remote storage path, once the upload has been confirmed.
  TextColumn get remotePath => text().nullable()();

  /// What the file is: `before`, `after`, `signature`, `document`.
  TextColumn get fileType => text()();

  /// Original file name (for display / download naming).
  TextColumn get fileName => text()();

  TextColumn get mimeType => text().nullable()();

  IntColumn get sizeBytes => integer().nullable()();

  /// When the photo was taken / the signature was captured.
  DateTimeColumn get capturedAt => dateTime()();

  // --- Local-only sync metadata -------------------------------------------------
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();

  DateTimeColumn get localUpdatedAt => dateTime().nullable()();

  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => <String>[
    'CONSTRAINT fk_job_files_job FOREIGN KEY (job_id) '
        'REFERENCES jobs (id) ON DELETE CASCADE',
  ];
}

/// Known kinds of job-attached files.
///
/// Deliberately an open set in the database (plain text) so future kinds do
/// not require a migration; this enum is the typed surface the app uses for
/// the kinds that exist today.
enum JobFileType {
  /// Photo of the site before work started.
  before,

  /// Photo of the site after work finished.
  after,

  /// Customer signature (e.g. proof of acceptance).
  signature,

  /// Any other document (contract scan, invoice, ...).
  document,
}
