import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:field_service/core/constants/app_constants.dart';

/// Creates the SQLite connection used by the application's Drift database.
///
/// Phase 3 status: **foundation only** — no tables, no `@DriftDatabase` class
/// and no generated code exist yet. This factory only fixes the decision of
/// *how* the database is opened (platform-aware file location, shared across
/// isolates) so the concrete database class can be added later without touching
/// any other layer.
///
/// Planned tables (implemented in the phase that builds offline storage):
/// * `employees` — technicians and admins cached from the backend
/// * `customers` — customer records
/// * `jobs` — renovation, kitchen installation and maintenance jobs
/// * `job_files` — metadata of photos, signatures and documents, while the
///   bytes live on disk behind `FileStorage`
/// * `sync_queue` / `pending_operations` — local changes waiting to be pushed
/// * `offline_changes` — audit of what changed while offline
/// * `sync_cursors` — last successful pull per aggregate, for delta sync
///
/// Architectural rule: Drift is an implementation detail of the **Data** layer.
/// Only data sources and repository implementations may import this file; the
/// Domain layer never sees a database type.
class AppDatabaseFactory {
  const AppDatabaseFactory({
    this.databaseName = AppConstants.databaseFileName,
    this.shareAcrossIsolates = true,
  });

  /// Base name of the database file (`<name>.sqlite`).
  final String databaseName;

  /// Lets a background isolate — the future sync worker — open the same
  /// database instance instead of competing for the file lock. Enabling it also
  /// makes stream queries consistent across isolates.
  final bool shareAcrossIsolates;

  /// Opens the platform-appropriate connection.
  ///
  /// Native platforms store `<documents>/<databaseName>.sqlite` through
  /// `path_provider`. Web would additionally require the `sqlite3.wasm` and
  /// `drift_worker.js` assets, which is out of scope for this mobile-first
  /// project for now.
  DatabaseConnection open() => driftDatabase(
    name: databaseName,
    native: DriftNativeOptions(shareAcrossIsolates: shareAcrossIsolates),
  );
}