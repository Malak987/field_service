import 'package:drift/drift.dart';
import 'package:field_service/core/database/tables/customers_table.dart';
import 'package:field_service/core/database/tables/job_events_table.dart';
import 'package:field_service/core/database/tables/job_files_table.dart';
import 'package:field_service/core/database/tables/jobs_table.dart';
import 'package:field_service/core/database/tables/sync_queue_table.dart';

part 'app_database.g.dart';

/// The application's local Drift database.
///
/// Architectural rule (unchanged from [AppDatabaseFactory]): Drift is an
/// implementation detail of the **Data** layer. Only data sources, the sync
/// engine and repository implementations may touch this class; the Domain
/// layer never sees a database type.
///
/// The database is the **source of truth for the UI** in the offline-first
/// design: screens read local rows, repositories write locally and enqueue
/// the change on the sync queue, and the sync engine pushes it when the
/// internet is available.
@DriftDatabase(
  tables: <Type>[
    SyncQueueTable,
    CustomersTable,
    JobsTable,
    JobEventsTable,
    JobFilesTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the database on any drift [QueryExecutor] (production:
  /// `AppDatabaseFactory().open()`; unit tests: an in-memory database).
  AppDatabase(super.executor);

  /// Current schema version. Bump it and extend [migration] for every
  /// schema change — the database is never deleted or recreated on upgrade.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      // Query support for the hot paths of the sync engine.
      await m.database.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sync_queue_status_created '
        'ON sync_queue (status, created_at)',
      );
      await m.database.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sync_queue_entity '
        'ON sync_queue (entity_type, entity_id)',
      );
      await m.database.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_customers_sync_status '
        'ON customers (sync_status, local_updated_at)',
      );
      await m.database.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_jobs_sync_status '
        'ON jobs (sync_status, local_updated_at)',
      );
      await m.database.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_jobs_assigned_employee '
        'ON jobs (assigned_employee_id)',
      );
      await m.database.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_job_events_job '
        'ON job_events (job_id, created_at)',
      );
      await m.database.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_job_files_job '
        'ON job_files (job_id)',
      );
      await m.database.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_job_files_sync_status '
        'ON job_files (sync_status)',
      );
      await _createRetentionTables(m);
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await _createRetentionTables(m);
      }
    },
    beforeOpen: (OpeningDetails details) async {
      // Self-healing migration: if sync_queue date columns were written as
      // ISO-8601 text strings, convert them back to unix epoch integers so
      // Drift's DateTime mapper parses them correctly without radix errors.
      await customStatement('''
        UPDATE sync_queue 
        SET created_at = CAST(strftime('%s', created_at) AS INTEGER) 
        WHERE typeof(created_at) = 'text' AND strftime('%s', created_at) IS NOT NULL;
      ''');
      await customStatement('''
        UPDATE sync_queue 
        SET updated_at = CAST(strftime('%s', updated_at) AS INTEGER) 
        WHERE typeof(updated_at) = 'text' AND strftime('%s', updated_at) IS NOT NULL;
      ''');
      await customStatement('''
        UPDATE sync_queue 
        SET last_attempt_at = CAST(strftime('%s', last_attempt_at) AS INTEGER) 
        WHERE typeof(last_attempt_at) = 'text' AND strftime('%s', last_attempt_at) IS NOT NULL;
      ''');
    },
  );

  Future<void> _createRetentionTables(Migrator m) async {
    // Separate tables keep this additive migration independent of generated
    // Drift row classes. Existing queue rows intentionally receive no owner:
    // they remain quarantined until ownership can be established safely.
    await m.database.customStatement('''
      CREATE TABLE IF NOT EXISTS sync_operation_scope (
        operation_id TEXT PRIMARY KEY REFERENCES sync_queue(id) ON DELETE CASCADE,
        job_id TEXT,
        owner_user_id TEXT,
        created_at_source TEXT NOT NULL DEFAULT 'unknown',
        created_at TEXT
      )
    ''');
    await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sync_scope_owner_job '
      'ON sync_operation_scope (owner_user_id, job_id)',
    );
    // Job-only lookups (terminal blocking, retention cleanup) cannot use the
    // owner-first index above.
    await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sync_scope_job '
      'ON sync_operation_scope (job_id)',
    );
    await m.database.customStatement('''
      CREATE TABLE IF NOT EXISTS local_job_retention (
        job_id TEXT PRIMARY KEY,
        original_created_at TEXT,
        created_at_source TEXT NOT NULL,
        created_by_user_id TEXT,
        authorized_sync_user_id TEXT,
        identity_state TEXT NOT NULL DEFAULT 'unknown',
        task_state TEXT NOT NULL DEFAULT 'active',
        expires_at TEXT,
        retention_state TEXT NOT NULL DEFAULT 'active',
        cleanup_step TEXT NOT NULL DEFAULT 'not_started',
        last_cleanup_error TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
    await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_job_retention_due '
      'ON local_job_retention (retention_state, expires_at)',
    );
  }

  // Note: typed access to the tables (`syncQueueTable`, `customersTable`,
  // `jobsTable`, `jobEventsTable`, `jobFilesTable`) is generated by drift on
  // `_$AppDatabase` and inherited by this class.
}
