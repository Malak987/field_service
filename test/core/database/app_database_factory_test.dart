import 'package:field_service/core/constants/app_constants.dart';
import 'package:field_service/core/database/app_database_factory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppDatabaseFactory', () {
    test('targets the application database file', () {
      const AppDatabaseFactory factory = AppDatabaseFactory();

      expect(factory.databaseName, AppConstants.databaseFileName);
      expect(
        factory.shareAcrossIsolates,
        isTrue,
        reason:
            'The future sync worker runs in its own isolate and must share the '
            'database instance instead of competing for the file lock.',
      );
    });

    test('accepts overrides for tests that need an isolated database', () {
      const AppDatabaseFactory factory = AppDatabaseFactory(
        databaseName: 'field_service_test',
        shareAcrossIsolates: false,
      );

      expect(factory.databaseName, 'field_service_test');
      expect(factory.shareAcrossIsolates, isFalse);
    });
  });
}
