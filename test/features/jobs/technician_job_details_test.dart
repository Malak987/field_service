import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/features/admin/presentation/pages/admin_home_page.dart';
import 'package:field_service/features/customers/data/datasources/customers_local_data_source.dart';
import 'package:field_service/features/customers/data/models/customer_model.dart';
import 'package:field_service/features/customers/domain/entities/customer_sync_status.dart';
import 'package:field_service/features/customers/presentation/pages/customers_page.dart';
import 'package:field_service/features/customers/presentation/widgets/customer_search_field.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/pages/job_details_page.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_error_state.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_list_item.dart';
import 'package:field_service/features/technician/presentation/pages/technician_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';

/// Jobs as the server would return them under RLS:
/// * `job-mine` — assigned to the signed-in technician,
/// * `job-other` — assigned to a DIFFERENT technician (never in the
///   signed-in technician's visible set; only used to attempt direct URLs).
Job _job({
  required String id,
  required int number,
  required String customerId,
  String? assignedEmployeeId,
  String? customerName,
}) {
  return Job(
    id: id,
    jobNumber: number,
    customerId: customerId,
    customerName: customerName,
    assignedEmployeeId: assignedEmployeeId,
    jobType: 'maintenance',
    description: 'Fix the sink.',
    status: const JobStatus(JobStatus.assigned),
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
    expiresAt: DateTime.utc(2026, 12, 1),
  );
}

/// What the `get_job_customer` RPC returns for `job-mine` (and only for it).
const JobCustomerInfo aliceInfo = JobCustomerInfo(
  name: 'Alice Customer',
  phone: '+20 100 111 2222',
  address: '10 Test Street',
  city: 'Sohag',
  postalCode: '82511',
);

void main() {
  late AppTestHarness app;
  setUp(() => app = AppTestHarness());
  tearDown(() => app.dispose());

  Job myJob({String? customerName}) => _job(
    id: 'job-mine',
    number: 101,
    customerId: 'cust-alice',
    assignedEmployeeId: 'emp-tech-1',
    customerName: customerName,
  );

  Job otherJob() => _job(
    id: 'job-other',
    number: 102,
    customerId: 'cust-bob',
    assignedEmployeeId: 'emp-tech-2',
  );

  /// Seeds the ADMIN Drift customers mirror — the cache a technician must
  /// never see surface anywhere.
  Future<void> seedAdminCustomerCache() async {
    final local = sl<CustomersLocalDataSource>();
    for (final name in ['Alice Customer', 'Bob Customer']) {
      await local.insert(
        CustomerModel(
          id: name == 'Alice Customer' ? 'cust-alice' : 'cust-bob',
          name: name,
          address: '10 Test Street',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
          syncStatus: CustomerSyncStatus.synced,
        ),
      );
    }
  }

  // Test 1 — the technician list shows exactly the RLS-visible set.
  _testJobDetails('technician sees only their assigned jobs', (tester) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[myJob()],
      jobCustomers: <String, JobCustomerInfo?>{'job-mine': aliceInfo},
    );
    await app.pump(tester);
    await tester.tap(find.text('View Jobs'));
    await tester.pumpAndSettle();

    expect(find.byType(JobsListItem), findsOneWidget);
    expect(find.text('#101'), findsOneWidget);
    expect(find.text('#102'), findsNothing);
  });

  // Test 2 — the assigned job's details expose that job's customer info.
  _testJobDetails(
    'technician opening their assigned job sees its customer information',
    (tester) async {
      await _tallSurface(tester);
      await app.configure(
        user: technicianUser,
        jobs: <Job>[myJob()],
        jobCustomers: <String, JobCustomerInfo?>{'job-mine': aliceInfo},
      );
      await app.pump(tester);
      await tester.tap(find.text('View Jobs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('#101'));
      await tester.pumpAndSettle();

      expect(find.byType(JobDetailsPage), findsOneWidget);
      // Job Information section.
      expect(find.text('Job Information'), findsOneWidget);
      expect(find.text('#101'), findsWidgets);
      expect(find.text('Maintenance'), findsWidgets);
      expect(find.text('Fix the sink.'), findsOneWidget);
      // Customer section — exactly this job's customer.
      expect(find.text('Alice Customer'), findsOneWidget);
      expect(find.text('+20 100 111 2222'), findsOneWidget);
      expect(find.text('10 Test Street'), findsOneWidget);
      expect(find.text('Sohag'), findsOneWidget);
      expect(find.text('82511'), findsOneWidget);
    },
  );

  // Test 3 — another technician's job: no data, error surface only.
  _testJobDetails(
    'technician opening another technician\'s job gets no data',
    (tester) async {
      await app.configure(
        user: technicianUser,
        jobs: <Job>[myJob()],
        jobCustomers: <String, JobCustomerInfo?>{'job-mine': aliceInfo},
      );
      await app.pump(tester);
      await tester.tap(find.text('View Jobs'));
      await tester.pumpAndSettle();

      app.router.go('/jobs/${otherJob().id}');
      await tester.pumpAndSettle();

      expect(find.byType(JobDetailsPage), findsOneWidget);
      expect(find.byType(JobsErrorState), findsOneWidget);
      expect(find.text('#102'), findsNothing);
      expect(find.text('Fix the sink.'), findsNothing);
      expect(find.text('Alice Customer'), findsNothing);
      expect(find.text('Job Information'), findsNothing);
    },
  );

  // Test 4 — customer data is reachable ONLY through the assigned job;
  // neither the cached admin mirror nor an arbitrary customer id helps.
  _testJobDetails(
    'technician cannot retrieve a customer by arbitrary customer id',
    (tester) async {
      await _tallSurface(tester);
      await app.configure(
        user: technicianUser,
        withCustomers: true,
        jobs: <Job>[myJob()],
        jobCustomers: <String, JobCustomerInfo?>{'job-mine': aliceInfo},
      );
      await seedAdminCustomerCache();
      await app.pump(tester);

      // The assigned job's details show ONLY the RPC-provided customer of
      // that job — the other cached (admin) customer never appears.
      await tester.tap(find.text('View Jobs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('#101'));
      await tester.pumpAndSettle();
      expect(find.text('Alice Customer'), findsOneWidget);
      expect(find.text('Bob Customer'), findsNothing);

      // Direct customer-by-id URLs stay refused (phase-1 guard intact).
      app.router.go('${AppRoutes.customers}/cust-bob');
      await tester.pumpAndSettle();
      expect(find.byType(TechnicianHomePage), findsOneWidget);
      expect(find.byType(CustomersPage), findsNothing);
      expect(find.text('Alice Customer'), findsNothing);
      expect(find.text('Bob Customer'), findsNothing);
    },
  );

  // Test 5 — `/customers` remains unreachable for technicians
  // (full route-set coverage lives in customers_navigation_test.dart).
  _testJobDetails('technician cannot access /customers', (tester) async {
    await app.configure(user: technicianUser, jobs: <Job>[myJob()]);
    await app.pump(tester);

    app.router.go(AppRoutes.customers);
    await tester.pumpAndSettle();

    expect(find.byType(TechnicianHomePage), findsOneWidget);
    expect(find.byType(CustomersPage), findsNothing);
    expect(find.text('Customers'), findsNothing);
  });

  // Test 6 — admin keeps full access: job list, job details and the same
  // per-job customer section (admin Customers feature is covered by
  // customers_navigation_test.dart and stays untouched).
  _testJobDetails('admin job details show the job\'s customer information', (
    tester,
  ) async {
    await _tallSurface(tester);
    await app.configure(
      user: adminUser,
      jobs: <Job>[myJob(customerName: 'Alice Customer'), otherJob()],
      jobCustomers: <String, JobCustomerInfo?>{'job-mine': aliceInfo},
    );
    await app.pump(tester);
    expect(find.byType(AdminHomePage), findsOneWidget);

    await tester.tap(find.text('View Jobs'));
    await tester.pumpAndSettle();
    expect(find.byType(JobsListItem), findsNWidgets(2));
    await tester.tap(find.text('#101'));
    await tester.pumpAndSettle();

    expect(find.byType(JobDetailsPage), findsOneWidget);
    expect(find.text('Job Information'), findsOneWidget);
    expect(find.text('Alice Customer'), findsOneWidget);
    expect(find.text('+20 100 111 2222'), findsOneWidget);
    expect(find.text('82511'), findsOneWidget);
  });

  // Test 7 — job details never expose the global customers surface.
  _testJobDetails(
    'technician job details expose no global customers list',
    (tester) async {
      await _tallSurface(tester);
      await app.configure(
        user: technicianUser,
        withCustomers: true,
        jobs: <Job>[myJob()],
        jobCustomers: <String, JobCustomerInfo?>{'job-mine': aliceInfo},
      );
      await seedAdminCustomerCache();
      await app.pump(tester);
      await tester.tap(find.text('View Jobs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('#101'));
      await tester.pumpAndSettle();

      expect(find.byType(JobDetailsPage), findsOneWidget);
      expect(find.text('Alice Customer'), findsOneWidget);
      // No list, no search, no customer-management actions of any kind.
      expect(find.byType(CustomersPage), findsNothing);
      expect(find.byType(CustomerSearchField), findsNothing);
      expect(find.byKey(const Key('add_customer_fab')), findsNothing);
      expect(find.byKey(const Key('edit_customer_button')), findsNothing);
      expect(find.byKey(const Key('delete_customer_button')), findsNothing);
      expect(find.text('Bob Customer'), findsNothing);
    },
  );

  // Test 8 — offline: job details degrade to the error state and leak
  // nothing from the cached admin customers mirror.
  _testJobDetails(
    'offline job details expose no unrelated cached customers',
    (tester) async {
      await app.configure(
        user: technicianUser,
        withCustomers: true,
        jobs: <Job>[myJob()],
        jobCustomers: <String, JobCustomerInfo?>{'job-mine': aliceInfo},
        jobsOffline: true,
      );
      await seedAdminCustomerCache();
      await app.pump(tester);

      // The list cannot load while offline...
      await tester.tap(find.text('View Jobs'));
      await tester.pumpAndSettle();
      expect(find.byType(JobsErrorState), findsOneWidget);
      expect(find.text('#101'), findsNothing);

      // ...and a direct details URL shows the error surface with zero
      // customer data, even though admin rows sit in the Drift cache.
      app.router.go('/jobs/job-mine');
      await tester.pumpAndSettle();
      expect(find.byType(JobDetailsPage), findsOneWidget);
      expect(find.byType(JobsErrorState), findsOneWidget);
      expect(find.text('Alice Customer'), findsNothing);
      expect(find.text('Bob Customer'), findsNothing);
      expect(find.text('Job Information'), findsNothing);
    },
  );
}

/// Tall surface: Job Details now stacks header + Start Job + Job Information
/// + Customer; on the default 800x600 canvas the customer card would sit
/// below the fold and default (onstage) finders skip offstage content.
Future<void> _tallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

// Drift defers stream-query cleanup by one event-loop turn. Dispose and drain
// inside the widget test's fake-async zone, before the database is closed.
void _testJobDetails(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}
