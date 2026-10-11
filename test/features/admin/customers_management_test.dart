import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/features/admin/domain/entities/admin_account_status.dart';
import 'package:field_service/features/admin/domain/entities/managed_customer.dart';
import 'package:field_service/features/admin/presentation/pages/admin_customers_page.dart';
import 'package:field_service/features/admin/domain/usecases/get_unavailable_customer_ids.dart';
import 'package:field_service/features/customers/data/datasources/customers_local_data_source.dart';
import 'package:field_service/features/customers/data/models/customer_model.dart';
import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/customers/domain/entities/customer_sync_status.dart';
import 'package:field_service/features/customers/domain/usecases/get_customers.dart';
import 'package:field_service/features/customers/domain/usecases/refresh_customers.dart';
import 'package:field_service/features/employees/domain/entities/employee.dart';
import 'package:field_service/features/employees/domain/usecases/get_active_technicians.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/domain/usecases/create_job.dart';
import 'package:field_service/features/jobs/presentation/cubit/create_job_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';

/// Customer management (`إدارة العملاء`) tests.
///
/// They cover exactly the requested scenarios: list with details and state,
/// add, edit, block (which removes the customer from NEW jobs while its old
/// jobs stay viewable), unblock, and the logical delete that preserves the
/// whole history.
///
/// The "server" behind the pages is the harness fake; the real enforcement
/// (admin-only RPCs, blocked customers refused inside `create_job`) is
/// implemented in `supabase/admin_management_setup.sql`.

const ManagedCustomer kActiveCustomer = ManagedCustomer(
  id: 'cust-active',
  name: 'Active Customer',
  address: '10 Test Street',
  phone: '+49 30 111 222',
  email: 'active@example.com',
  city: 'Giza',
  postalCode: '12511',
  jobsCount: 2,
);

const ManagedCustomer kBlockedCustomer = ManagedCustomer(
  id: 'cust-blocked',
  name: 'Blocked Customer',
  address: '20 Oak Avenue',
  status: AdminAccountStatus.blocked,
  jobsCount: 3,
);

const ManagedCustomer kDeletedCustomer = ManagedCustomer(
  id: 'cust-deleted',
  name: 'Deleted Customer',
  address: '30 Pine Road',
  status: AdminAccountStatus.deleted,
  jobsCount: 1,
);

const Employee kMaxMueller = Employee(
  id: 'emp-max',
  name: 'Max Müller',
  role: 'technician',
);

Job _jobFor(String customerId, {int number = 7}) {
  return Job(
    id: 'job-$customerId',
    jobNumber: number,
    customerId: customerId,
    assignedEmployeeId: 'emp-max',
    jobType: JobCategory.kitchenRenovation,
    description: 'Customer wants the kitchen renovated.',
    status: JobStatus(JobStatus.assigned),
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
    expiresAt: DateTime.utc(2026, 12, 1),
  );
}

void main() {
  late AppTestHarness app;

  setUp(() => app = AppTestHarness());
  tearDown(() => app.dispose());

  Future<void> tallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<void> openCustomers(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('nav_admin_customers')));
    await tester.tap(find.byKey(const Key('nav_admin_customers')));
    await tester.pumpAndSettle();
    expect(find.byType(AdminCustomersPage), findsOneWidget);
  }

  Future<void> tapAndConfirm(WidgetTester tester, Key actionKey) async {
    await tester.ensureVisible(find.byKey(actionKey));
    await tester.tap(find.byKey(actionKey));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin_confirm_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin_confirm_accept')));
    await tester.pumpAndSettle();
  }

  Future<void> seedLocalCustomer(ManagedCustomer customer) async {
    await sl<CustomersLocalDataSource>().insert(
      CustomerModel(
        id: customer.id,
        name: customer.name,
        address: customer.address,
        phone: customer.phone,
        email: customer.email,
        city: customer.city,
        postalCode: customer.postalCode,
        notes: customer.notes,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        syncStatus: CustomerSyncStatus.synced,
      ),
    );
  }

  testWidgets('lists customers with their details and their state', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(
      user: adminUser,
      adminCustomers: const <ManagedCustomer>[
        kActiveCustomer,
        kBlockedCustomer,
        kDeletedCustomer,
      ],
    );
    await app.pump(tester);
    await openCustomers(tester);

    expect(find.text('Active Customer'), findsOneWidget);
    expect(find.text('Blocked Customer'), findsOneWidget);
    expect(find.text('Deleted Customer'), findsOneWidget);

    // Details of every record are visible (address, city, phone, job count).
    expect(find.text('10 Test Street, Giza, 12511'), findsOneWidget);
    expect(find.text('+49 30 111 222'), findsOneWidget);
    expect(find.text('2 jobs'), findsOneWidget);
    expect(find.text('3 jobs'), findsOneWidget);

    // The state is shown for each row.
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Blocked'), findsOneWidget);
    expect(find.text('Deleted'), findsOneWidget);

    // Deleted rows are read-only: no edit, no block, no delete.
    expect(
      find.byKey(const Key('admin_customer_edit_cust-deleted')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('admin_customer_block_cust-deleted')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('admin_customer_delete_cust-deleted')),
      findsNothing,
    );
  });

  testWidgets('the admin creates a customer through the management form', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(user: adminUser);
    await app.pump(tester);
    await openCustomers(tester);

    expect(find.text('No customers yet'), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin_add_customer_fab')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'New Customer'
    );
    await tester.enterText(
      find.byType(TextFormField).at(3),
      '99 New Street',
    );

    final Finder save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(app.adminCreatedCustomers, hasLength(1));
    expect(app.adminCreatedCustomers.single['name'], 'New Customer');
    expect(app.adminCreatedCustomers.single['address'], '99 New Street');
    expect(find.text('Customer created.'), findsOneWidget);

    // The list refreshed on return: the new record is there.
    expect(find.text('New Customer'), findsOneWidget);
  });

  testWidgets('the admin edits a customer', (tester) async {
    await tallSurface(tester);
    await app.configure(
      user: adminUser,
      adminCustomers: const <ManagedCustomer>[kActiveCustomer],
    );
    await app.pump(tester);
    await openCustomers(tester);

    await tester.ensureVisible(
      find.byKey(const Key('admin_customer_edit_cust-active')),
    );
    await tester.tap(find.byKey(const Key('admin_customer_edit_cust-active')));
    await tester.pumpAndSettle();

    // The form is pre-filled with the stored values.
    expect(find.text('Active Customer'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Renamed Customer',
    );
    final Finder save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(app.adminUpdatedCustomers.single['id'], 'cust-active');
    expect(app.adminUpdatedCustomers.single['name'], 'Renamed Customer');
    expect(find.text('Customer updated.'), findsOneWidget);
    expect(find.text('Renamed Customer'), findsOneWidget);
  });

  testWidgets('blocking and unblocking a customer ask for confirmation', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(
      user: adminUser,
      adminCustomers: const <ManagedCustomer>[kActiveCustomer],
    );
    await app.pump(tester);
    await openCustomers(tester);

    await tapAndConfirm(tester, const Key('admin_customer_block_cust-active'));
    expect(app.adminCustomerStatusChanges, <Map<String, Object?>>[
      <String, Object?>{'customer_id': 'cust-active', 'status': 'blocked'},
    ]);
    expect(app.adminCustomers.single.status, AdminAccountStatus.blocked);
    expect(find.text('Customer blocked.'), findsOneWidget);
    expect(find.text('Blocked'), findsOneWidget);

    // Unblock: the customer is usable for new jobs again.
    await tapAndConfirm(tester, const Key('admin_customer_unblock_cust-active'));
    expect(app.adminCustomerStatusChanges.last, <String, Object?>{
      'customer_id': 'cust-active',
      'status': 'active',
    });
    expect(app.adminCustomers.single.status, AdminAccountStatus.active);
    expect(find.text('Customer unblocked.'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets('the logical delete keeps the customer and its history', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(
      user: adminUser,
      adminCustomers: const <ManagedCustomer>[kActiveCustomer],
    );
    await app.pump(tester);
    await openCustomers(tester);

    await tapAndConfirm(tester, const Key('admin_customer_delete_cust-active'));

    final ManagedCustomer stored = app.adminCustomers.single;
    expect(stored.status, AdminAccountStatus.deleted);
    expect(stored.name, 'Active Customer');
    expect(stored.jobsCount, 2);
    expect(stored.deletedAt, isNotNull);

    expect(find.text('Customer deleted (history preserved).'), findsOneWidget);
    expect(find.text('Deleted'), findsOneWidget);
    // The two historical jobs are still counted — nothing was cascaded away.
    expect(find.text('2 jobs'), findsOneWidget);
    expect(find.byKey(const Key('admin_customer_edit_cust-active')), findsNothing);
    expect(find.byKey(const Key('admin_customer_block_cust-active')), findsNothing);
  });

  testWidgets(
    'a blocked customer cannot be chosen for a new job, its old job stays',
    (tester) async {
      await tallSurface(tester);
      final Job historicalJob = _jobFor('cust-blocked');
      await app.configure(
        user: adminUser,
        withCustomers: true,
        technicians: const <Employee>[kMaxMueller],
        adminCustomers: const <ManagedCustomer>[kBlockedCustomer],
        jobs: <Job>[historicalJob],
        jobCustomers: <String, JobCustomerInfo?>{
          historicalJob.id: const JobCustomerInfo(
            name: 'Blocked Customer',
            address: '20 Oak Avenue',
          ),
        },
      );
      await seedLocalCustomer(kBlockedCustomer);
      await seedLocalCustomer(kActiveCustomer);

      await app.pump(tester);

      // The Create Job selector asks the server which customers it refuses and
      // removes them — the mirror still holds the blocked row, the FORM does
      // not offer it.
      app.router.go(AppRoutes.jobCreate);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create_job_customer_dropdown')));
      await tester.pumpAndSettle();
      expect(find.text('Active Customer'), findsOneWidget);
      expect(find.text('Blocked Customer'), findsNothing);
      expect(app.unavailableCustomerIdCalls, greaterThanOrEqualTo(1));

      // The historical job of the blocked customer is NOT hidden anywhere.
      app.router.go(AppRoutes.jobs);
      await tester.pumpAndSettle();
      expect(find.text('#${historicalJob.jobNumber}'), findsOneWidget);
    },
  );

  testWidgets('customer details show the stored record and its state', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(
      user: adminUser,
      adminCustomers: const <ManagedCustomer>[kBlockedCustomer],
    );
    await app.pump(tester);
    await openCustomers(tester);

    await tester.tap(find.text('Blocked Customer'));
    await tester.pumpAndSettle();

    expect(find.text('Customer details'), findsOneWidget);
    expect(find.text('20 Oak Avenue'), findsWidgets);
    expect(find.text('3 jobs'), findsOneWidget);
    expect(find.text('Blocked'), findsOneWidget);

    // The details page offers the same guarded transition as the list.
    await tapAndConfirm(
      tester,
      const Key('admin_customer_details_unblock_cust-blocked'),
    );
    expect(app.adminCustomerStatusChanges.single, <String, Object?>{
      'customer_id': 'cust-blocked',
      'status': 'active',
    });
    expect(find.text('Customer unblocked.'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Cubit level: the screening itself (client filter + server refusal)
  // ---------------------------------------------------------------------------

  test('the Create Job options exclude the customers the server refuses', () async {
    final Customer blocked = Customer(
      id: 'cust-blocked',
      name: 'Blocked Customer',
      address: '20 Oak Avenue',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: CustomerSyncStatus.synced,
    );
    final Customer active = Customer(
      id: 'cust-active',
      name: 'Active Customer',
      address: '10 Test Street',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: CustomerSyncStatus.synced,
    );
    final CreateJobCubit cubit = CreateJobCubit(
      getCustomers: _CustomerStream(<Customer>[blocked, active]),
      getActiveTechnicians: _StubTechnicians(),
      createJob: _UnusedCreateJob(),
      refreshCustomers: _SpyRefreshCustomers(),
      getUnavailableCustomerIds: _UnavailableCustomers(
        const <String>{'cust-blocked'},
      ),
    );

    await cubit.loadOptions();
    await Future<void>.delayed(Duration.zero);

    expect(
      cubit.state.customers.map((Customer c) => c.id),
      <String>['cust-active'],
    );
    expect(cubit.state.unavailableCustomerIds, <String>{'cust-blocked'});

    // Even a programmatic selection of a refused customer is ignored.
    cubit.selectCustomer('cust-blocked');
    expect(cubit.state.selectedCustomerId, isNull);
    await cubit.close();
  });
}

// --- Local fakes (mirror the ones used by the Create Job tests) --------------

class _CustomerStream implements GetCustomers {
  _CustomerStream(this.customers);

  final List<Customer> customers;

  @override
  Stream<List<Customer>> call() => Stream<List<Customer>>.value(customers);
}

class _StubTechnicians implements GetActiveTechnicians {
  @override
  Future<List<Employee>> call() async => const <Employee>[];
}

class _UnusedCreateJob implements CreateJob {
  @override
  Future<Job> call({
    required String customerId,
    required String jobType,
    String? description,
    required String assignedEmployeeId,
  }) {
    throw UnimplementedError('This test never submits a job.');
  }
}

class _SpyRefreshCustomers implements RefreshCustomers {
  @override
  Future<void> call() async {}
}

class _UnavailableCustomers implements GetUnavailableCustomerIds {
  _UnavailableCustomers(this.ids);

  final Set<String> ids;

  @override
  Future<Set<String>> call() async => ids;
}
