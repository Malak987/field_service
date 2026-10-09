import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/sync/sync_queue.dart';
import 'package:field_service/features/admin/presentation/pages/admin_home_page.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
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
          address: name.startsWith('Alice')
              ? '10 Test Street'
              : '20 Oak Avenue',
          phone: name.startsWith('Alice') ? '+20 100 111 2222' : '+20 100 333 4444',
          email: name.startsWith('Alice')
              ? 'alice@example.com'
              : 'bob@example.com',
          city: name.startsWith('Alice') ? 'Giza' : 'Cairo',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
          syncStatus: CustomerSyncStatus.synced,
        ),
      );
    }
  }

  /// Simulates the next account signing in through the shared authentication
  /// session (same mechanism the app sees from Supabase after a login).
  Future<void> signInAs(WidgetTester tester, AppUser user) async {
    app.authentication.currentUser = user;
    app.authentication.events.add(AuthSessionEvent.signedIn);
    await tester.pumpAndSettle();
  }

  Future<void> signOutFromHome(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Sign Out'));
    await tester.pumpAndSettle();
    expect(app.authentication.currentUser, isNull);
    expect(find.byType(LoginPage), findsOneWidget);
  }

  // Test 1 / Test 5 prerequisite: the admin surface keeps working end-to-end.
  _testCustomers('admin: home → Customers → search → details → home', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await app.configure(user: adminUser, withCustomers: true);
    await seedCustomers();
    await app.pump(tester);
    expect(find.text('View Jobs'), findsOneWidget);
    await tester.tap(find.text('Customers'));
    await tester.pumpAndSettle();
    expect(find.byType(CustomersPage), findsOneWidget);
    expect(find.text('Alice Customer'), findsOneWidget);
    expect(find.text('Bob Customer'), findsOneWidget);
    expect(find.text('2 customers'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.byKey(const Key('add_customer_fab')), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bob@example.com');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Alice Customer'), findsNothing);
    expect(find.text('Bob Customer'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '333 4444');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Alice Customer'), findsNothing);
    expect(find.text('Bob Customer'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '20 Oak Avenue');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Alice Customer'), findsNothing);
    expect(find.text('Bob Customer'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Alice Customer'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Bob Customer'), findsNothing);
    await tester.tap(find.text('Alice Customer'));
    await tester.pumpAndSettle();
    expect(find.byType(CustomerDetailsPage), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('edit_customer_button')), findsOneWidget);
    expect(find.byKey(const Key('delete_customer_button')), findsOneWidget);

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
    expect(find.byType(AdminHomePage), findsOneWidget);
  });

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
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('This field is required.'), findsNWidgets(2));

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Offline Customer',
      );
      await tester.enterText(
        find.byType(TextFormField).at(3),
        '10 Offline Street',
      );
      await tester.enterText(find.byType(TextFormField).at(2), 'not-an-email');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter a valid email address.'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'offline@example.com',
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomersPage), findsOneWidget);
      expect(find.text('Offline Customer'), findsOneWidget);
      expect(find.text('Customer saved successfully.'), findsOneWidget);
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

  // Test 2 (UI half): the technician dashboard has no Customers section.
  _testCustomers('technician dashboard exposes no Customers entry point', (
    tester,
  ) async {
    await app.configure(user: technicianUser, withCustomers: true);
    await seedCustomers();
    await app.pump(tester);
    expect(find.byType(TechnicianHomePage), findsOneWidget);
    expect(find.text('View Jobs'), findsOneWidget);
    expect(find.text('Customers'), findsNothing);
    expect(find.byIcon(Icons.people_outline), findsNothing);
    expect(find.byType(CustomersPage), findsNothing);
  });

  // Test 3 — the exact reported cache leak:
  // admin caches customers → logs out → technician logs in → nothing leaks.
  _testCustomers(
    'cached admin customers stay invisible after switching to a technician',
    (tester) async {
      await app.configure(user: adminUser, withCustomers: true);
      await seedCustomers();
      await app.pump(tester);

      // 1) Admin opens Customers — the rows are served by the Drift mirror.
      await tester.tap(find.text('Customers'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomersPage), findsOneWidget);
      expect(find.text('Alice Customer'), findsOneWidget);
      expect(find.text('Bob Customer'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(AdminHomePage), findsOneWidget);

      // 2) Admin logs out, technician logs in.
      await signOutFromHome(tester);
      await signInAs(tester, technicianUser);
      expect(find.byType(TechnicianHomePage), findsOneWidget);

      // 3) No Customers section and no previously cached admin rows anywhere.
      expect(find.text('Customers'), findsNothing);
      expect(find.byType(CustomersPage), findsNothing);
      expect(find.byType(CustomerDetailsPage), findsNothing);
      expect(find.text('Alice Customer'), findsNothing);
      expect(find.text('Bob Customer'), findsNothing);

      // 4) The offline database itself was NOT wiped — the admin mirror is
      //    still there for the next admin session (jobs/queue untouched too).
      final rows = await app.database!
          .select(app.database!.customersTable)
          .get();
      expect(rows.length, 2);
    },
  );

  // Test 4: direct `/customers` URLs are refused for technicians — both as a
  // cold-start URL and as an in-session navigation attempt.
  for (final path in [
    AppRoutes.customers,
    AppRoutes.customerCreate,
    '/customers/Alice%20Customer',
    '/customers/Alice%20Customer/edit',
  ]) {
    _testCustomers('technician navigating to $path is redirected home', (
      tester,
    ) async {
      await app.configure(user: technicianUser, withCustomers: true);
      await seedCustomers();
      await app.pump(tester);

      app.router.go(path);
      await tester.pumpAndSettle();

      expect(
        app.router.routeInformationProvider.value.uri.path,
        AppRoutes.root,
      );
      expect(find.byType(TechnicianHomePage), findsOneWidget);
      expect(find.byType(CustomersPage), findsNothing);
      expect(find.byType(CustomerDetailsPage), findsNothing);
      expect(find.byType(CreateCustomerPage), findsNothing);
      expect(find.byType(EditCustomerPage), findsNothing);
      expect(find.text('Alice Customer'), findsNothing);
      expect(find.text('Bob Customer'), findsNothing);
    });
  }

  _testCustomers('technician cold-starting on /customers lands on dashboard', (
    tester,
  ) async {
    await app.configure(
      user: technicianUser,
      initialLocation: AppRoutes.customers,
      withCustomers: true,
    );
    await seedCustomers();
    await app.pump(tester);

    expect(find.byType(TechnicianHomePage), findsOneWidget);
    expect(find.byType(CustomersPage), findsNothing);
    expect(find.text('Alice Customer'), findsNothing);
  });

  // Test 5: after a technician session, the admin gets Customers back intact.
  _testCustomers('admin login after a technician restores full Customers', (
    tester,
  ) async {
    await app.configure(user: technicianUser, withCustomers: true);
    await seedCustomers();
    await app.pump(tester);
    expect(find.byType(TechnicianHomePage), findsOneWidget);
    expect(find.text('Customers'), findsNothing);

    await signOutFromHome(tester);
    await signInAs(tester, adminUser);
    expect(find.byType(AdminHomePage), findsOneWidget);

    await tester.tap(find.text('Customers'));
    await tester.pumpAndSettle();
    expect(find.byType(CustomersPage), findsOneWidget);
    expect(find.text('Alice Customer'), findsOneWidget);
    expect(find.text('Bob Customer'), findsOneWidget);
    expect(find.byKey(const Key('add_customer_fab')), findsOneWidget);
  });

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
