import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:field_service/core/constants/app_constants.dart';

/// Creates the platform-specific SQLite connection used by [AppDatabase].
///
/// Native platforms use Drift's application-documents database and optional
/// cross-isolate sharing. Web uses SQLite compiled to WebAssembly and Drift's
/// worker; the matching `sqlite3.wasm` and `drift_worker.js` assets live in the
/// app's `web/` directory and are served from the app base URL.
///
/// Keep those two web assets aligned with the `sqlite3` and `drift` versions in
/// `pubspec.lock` when upgrading either dependency.
class AppDatabaseFactory {
  const AppDatabaseFactory({
    this.databaseName = AppConstants.databaseFileName,
    this.shareAcrossIsolates = true,
  });

  /// Database name without a file extension.
  final String databaseName;

  /// Lets native Flutter isolates share the same Drift database instance.
  final bool shareAcrossIsolates;

  /// Opens the platform-appropriate Drift connection.
  ///
  /// On web the connection opens lazily, so the WASM and worker assets are
  /// fetched only when the database is first used.
  DatabaseConnection open() => driftDatabase(
    name: databaseName,
    native: DriftNativeOptions(shareAcrossIsolates: shareAcrossIsolates),
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );
}
