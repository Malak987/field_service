import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/sync/sync_queue.dart';
import 'package:field_service/features/admin/presentation/pages/admin_home_page.dart';
import 'package:field_service/features/authentication/domain/entities/auth_session_event.dart';
import 'package:field_service/features/authentication/presentation/pages/login_page.dart';
import 'package:field_service/features/customers/data/datasources/customers_local_data_source.dart';
import 'package:field_service/features/customers/data/models/customer_model.dart';
import 'package:field_service/features/customers/domain/entities/customer_sync_status.dart';
import 'package:field_service/features/customers/domain/repositories/customers_repository.dart';
import 'package:field_service/features/customers/presentation/pages/create_customer_page.dart';
import 'package:field_service/features/customers/presentation/pages/customer_details_page.dart';
import 'package:field_service/features/customers/presentation/pages/customers_page.dart';
import 'package:field_service/features/customers/presentation/pages/edit_customer_page.dart';
import 'package:field_service/features/technician/presentation/pages/technician_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';

void main() {
  late AppTestHarness app;
  setUp(() => app = AppTestHarness());
  tearDown(() => app.dispose());

  Future<void> seedCustomers() async {
    final local = sl<CustomersLocalDataSource>();
    for (final name in ['Alice Customer', 'Bob Customer']) {
      await local.insert(
        CustomerModel(
          id: name,
          name: name,
          address: '10 Test Street',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
          syncStatus: CustomerSyncStatus.synced,
        ),
      );
    }
  }

  for (final user in [adminUser, technicianUser]) {
    _testCustomers('${user.role}: home → Customers → search → details → home', (
      tester,
    ) async {
      await app.configure(user: user, withCustomers: true);
      await seedCustomers();
      await app.pump(tester);
      expect(find.text('View Jobs'), findsOneWidget);
      await tester.tap(find.text('Customers'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomersPage), findsOneWidget);
      expect(find.text('Alice Customer'), findsOneWidget);
      expect(find.text('Bob Customer'), findsOneWidget);
      expect(
        find.byKey(const Key('add_customer_fab')),
        user.isAdmin ? findsOneWidget : findsNothing,
      );

      await tester.enterText(find.byType(TextField), 'Alice');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Bob Customer'), findsNothing);
      await tester.tap(find.text('Alice Customer'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomerDetailsPage), findsOneWidget);
      expect(
        find.byKey(const Key('edit_customer_button')),
        user.isAdmin ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const Key('delete_customer_button')),
        user.isAdmin ? findsOneWidget : findsNothing,
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(CustomersPage), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Alice',
      );
      expect(find.text('Bob Customer'), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(
        find.byType(user.isAdmin ? AdminHomePage : TechnicianHomePage),
        findsOneWidget,
      );
    });
  }

  _testCustomers(
    'existing admin forms create/edit/delete through Drift and queue',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await app.configure(user: adminUser, withCustomers: true);
      await app.pump(tester);
      await tester.tap(find.text('Customers'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add_customer_fab')));
      await tester.pumpAndSettle();
      expect(find.byType(CreateCustomerPage), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Offline Customer',
      );
      await tester.enterText(
        find.byType(TextFormField).at(3),
        '10 Offline Street',
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomersPage), findsOneWidget);
      expect(find.text('Offline Customer'), findsOneWidget);
      final row = await app.database!
          .select(app.database!.customersTable)
          .getSingle();
      expect(row.name, 'Offline Customer');
      expect(row.syncStatus, 'pending');
      expect(await sl<SyncQueue>().pendingCount(), 1);

      await tester.tap(find.text('Offline Customer'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomerDetailsPage), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('edit_customer_button')));
      await tester.tap(find.byKey(const Key('edit_customer_button')));
      await tester.pumpAndSettle();
      expect(find.byType(EditCustomerPage), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Edited Offline Customer',
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomerDetailsPage), findsOneWidget);
      expect(find.text('Edited Offline Customer'), findsOneWidget);
      expect(
        (await sl<CustomersRepository>().getCustomerById(row.id))!.name,
        'Edited Offline Customer',
      );
      expect(await sl<SyncQueue>().pendingCount(), 2);

      await tester.ensureVisible(
        find.byKey(const Key('delete_customer_button')),
      );
      await tester.tap(find.byKey(const Key('delete_customer_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_customer_confirm')));
      await tester.pumpAndSettle();
      expect(find.byType(CustomersPage), findsOneWidget);
      expect(find.text('Edited Offline Customer'), findsNothing);
      expect(await sl<CustomersRepository>().getCustomerById(row.id), isNull);
      expect(await sl<SyncQueue>().pendingCount(), 3);
      expect(await sl<SyncQueue>().failedCount(), 0);
    },
  );

  for (final path in [
    AppRoutes.customerCreate,
    '/customers/Alice%20Customer/edit',
  ]) {
    _testCustomers('technician cannot open mutation form by URL: $path', (
      tester,
    ) async {
      await app.configure(user: technicianUser, withCustomers: true);
      await seedCustomers();
      await app.pump(tester);
      app.router.go(path);
      await tester.pumpAndSettle();
      expect(
        app.router.routeInformationProvider.value.uri.path,
        AppRoutes.customers,
      );
      expect(find.byType(CustomersPage), findsOneWidget);
      expect(find.byType(CreateCustomerPage), findsNothing);
      expect(find.byType(EditCustomerPage), findsNothing);
      expect(find.byKey(const Key('add_customer_fab')), findsNothing);
      expect(find.text('Save'), findsNothing);
    });
  }

  _testCustomers(
    'signedOut on a pushed customer details route removes the stack',
    (tester) async {
      await app.configure(user: adminUser, withCustomers: true);
      await seedCustomers();
      await app.pump(tester);
      await tester.tap(find.text('Customers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alice Customer'));
      await tester.pumpAndSettle();
      app.authentication.currentUser = null;
      app.authentication.events.add(AuthSessionEvent.signedOut);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(CustomersPage), findsNothing);
      expect(find.byType(CustomerDetailsPage), findsNothing);
      expect(app.router.canPop(), isFalse);
    },
  );
}

// Drift defers stream-query cleanup by one event-loop turn. Dispose and drain
// inside the widget test's fake-async zone, before the database is closed.
void _testCustomers(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}
