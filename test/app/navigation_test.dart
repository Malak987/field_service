import 'dart:io';

import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/features/admin/presentation/pages/admin_home_page.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/domain/entities/auth_session_event.dart';
import 'package:field_service/features/authentication/presentation/pages/login_page.dart';
import 'package:field_service/features/customers/data/datasources/customers_local_data_source.dart';
import 'package:field_service/features/customers/data/models/customer_model.dart';
import 'package:field_service/features/customers/domain/entities/customer_sync_status.dart';
import 'package:field_service/features/customers/presentation/pages/create_customer_page.dart';
import 'package:field_service/features/customers/presentation/pages/customer_details_page.dart';
import 'package:field_service/features/customers/presentation/pages/customers_page.dart';
import 'package:field_service/features/customers/presentation/pages/edit_customer_page.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/pages/job_details_page.dart';
import 'package:field_service/features/jobs/presentation/pages/jobs_page.dart';
import 'package:field_service/features/jobs/presentation/services/photo_picker.dart';
import 'package:field_service/features/jobs/presentation/utils/jobs_date_format.dart';
import 'package:field_service/features/jobs/presentation/widgets/before_photo_tile.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_list_item.dart';
import 'package:field_service/features/technician/presentation/pages/technician_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_test_harness.dart';
import '../support/test_authentication_repository.dart';
import '../support/test_photos.dart';

/// Navigation & feature-access integration tests.
///
/// Verifies that the implemented features (Jobs, Job Details workflow,
/// Customers) are reachable through the real UI navigation for the right
/// roles — and that role switching, the router guards and the existing
/// technician workflow all keep working through it.

Job _job({
  required String id,
  required int number,
  String? assignedEmployeeId = 'emp-tech-1',
  String status = JobStatus.assigned,
}) {
  return Job(
    id: id,
    jobNumber: number,
    customerId: 'cust-$id',
    assignedEmployeeId: assignedEmployeeId,
    jobType: 'maintenance',
    description: 'Fix the sink.',
    status: JobStatus(status),
    startedAt: null,
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
    expiresAt: DateTime.utc(2026, 12, 1),
  );
}

/// Fake camera for the workflow regression test.
class _CameraPicker implements PhotoPicker {
  _CameraPicker(this.paths);

  final List<String> paths;
  int _index = 0;

  @override
  Future<PickedPhoto?> pick({required PhotoPickSource source}) async {
    if (_index >= paths.length) {
      return null;
    }
    return PickedPhoto(path: paths[_index++], mimeType: 'image/jpeg');
  }
}

void main() {
  late AppTestHarness app;
  late Directory tempDir;

  setUp(() {
    app = AppTestHarness();
    tempDir = Directory.systemTemp.createTempSync('navigation_test');
  });

  tearDown(() async {
    await app.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<void> tallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<void> signInAs(WidgetTester tester, AppUser user) async {
    app.authentication.currentUser = user;
    app.authentication.events.add(AuthSessionEvent.signedIn);
    await tester.pumpAndSettle();
  }

  Future<void> signOutFromHome(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Sign Out'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  }

  Future<void> seedCustomer(String name) async {
    await sl<CustomersLocalDataSource>().insert(
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

  // ---------------------------------------------------------------------------
  // Admin navigation
  // ---------------------------------------------------------------------------

  // Checklist 1: admin login reaches the admin UI + its navigation.
  testWidgets('admin login reaches the admin navigation', (tester) async {
    await app.configure(
      user: adminUser,
      jobs: <Job>[_job(id: 'job-1', number: 101)],
    );
    await app.pump(tester);

    expect(find.byType(AdminHomePage), findsOneWidget);
    expect(find.byType(TechnicianHomePage), findsNothing);
    // The two implemented features are exposed as navigation tiles.
    expect(find.byKey(const Key('nav_jobs')), findsOneWidget);
    expect(find.byKey(const Key('nav_customers')), findsOneWidget);
    expect(find.text('View Jobs'), findsOneWidget);
    expect(find.text('Customers'), findsOneWidget);
  });

  // Checklist 2: Admin → Jobs → Job Details → Back.
  testWidgets('admin navigates Jobs → Job Details → back', (tester) async {
    await app.configure(
      user: adminUser,
      jobs: <Job>[_job(id: 'job-1', number: 101)],
    );
    await app.pump(tester);

    await tester.tap(find.byKey(const Key('nav_jobs')));
    await tester.pumpAndSettle();
    expect(find.byType(JobsPage), findsOneWidget);

    await tester.tap(find.text('#101'));
    await tester.pumpAndSettle();
    expect(find.byType(JobDetailsPage), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(JobsPage), findsOneWidget);
    expect(find.byType(JobDetailsPage), findsNothing);
  });

  // Checklist 3–5: Admin → Customers → Customer Details → back → home.
  testWidgets('admin navigates Customers → details → back to home', (
    tester,
  ) async {
    await app.configure(user: adminUser, withCustomers: true);
    await seedCustomer('Alice Customer');
    await app.pump(tester);

    await tester.tap(find.byKey(const Key('nav_customers')));
    await tester.pumpAndSettle();
    expect(find.byType(CustomersPage), findsOneWidget);
    expect(find.text('Alice Customer'), findsOneWidget);

    await tester.tap(find.text('Alice Customer'));
    await tester.pumpAndSettle();
    expect(find.byType(CustomerDetailsPage), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(CustomersPage), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(AdminHomePage), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Technician navigation
  // ---------------------------------------------------------------------------

  // Checklist 6 + 9: technician home exposes Jobs — and no Customers item.
  testWidgets('technician navigation shows Jobs and never Customers', (
    tester,
  ) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-1', number: 101)],
    );
    await app.pump(tester);

    expect(find.byType(TechnicianHomePage), findsOneWidget);
    expect(find.byType(AdminHomePage), findsNothing);
    expect(find.byKey(const Key('nav_jobs')), findsOneWidget);
    expect(find.byKey(const Key('nav_customers')), findsNothing);
    expect(find.text('Customers'), findsNothing);
  });

  // Checklist 7–8 + back behavior: Jobs → Job Details → back, no duplicates.
  testWidgets('technician navigates Jobs → details → back without duplicates', (
    tester,
  ) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(id: 'job-1', number: 101),
        _job(id: 'job-2', number: 102),
      ],
    );
    await app.pump(tester);

    await tester.tap(find.byKey(const Key('nav_jobs')));
    await tester.pumpAndSettle();
    expect(find.byType(JobsPage), findsOneWidget);
    expect(find.byType(JobsListItem), findsNWidgets(2));

    await tester.tap(find.text('#101'));
    await tester.pumpAndSettle();
    expect(find.byType(JobDetailsPage), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    // Exactly one list page again — no duplicate cubit/page on return.
    expect(find.byType(JobsPage), findsOneWidget);
    expect(find.byType(JobsListItem), findsNWidgets(2));
  });

  // Repeated taps of a navigation item must not stack duplicate pages.
  testWidgets('repeated taps on the jobs tile stay on one jobs page', (
    tester,
  ) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-1', number: 101)],
    );
    await app.pump(tester);

    await tester.tap(find.byKey(const Key('nav_jobs')));
    // Second tap before the navigation settles (`go` never stacks).
    await tester.pump();
    if (find.byKey(const Key('nav_jobs')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('nav_jobs')));
    }
    await tester.pumpAndSettle();

    expect(find.byType(JobsPage), findsOneWidget);
  });

  // Checklist 10: every /customers URL stays blocked for technicians.
  testWidgets('technician is blocked from every customers route', (
    tester,
  ) async {
    await app.configure(
      user: technicianUser,
      withCustomers: true,
      jobs: <Job>[_job(id: 'job-1', number: 101)],
    );
    await app.pump(tester);

    for (final String blocked in <String>[
      AppRoutes.customers,
      AppRoutes.customerCreate,
      '/customers/cust-1',
      '/customers/cust-1/edit',
    ]) {
      app.router.go(blocked);
      await tester.pumpAndSettle();

      expect(find.byType(TechnicianHomePage), findsOneWidget, reason: blocked);
      expect(find.byType(CustomersPage), findsNothing, reason: blocked);
      expect(find.byType(CreateCustomerPage), findsNothing, reason: blocked);
      expect(find.byType(CustomerDetailsPage), findsNothing, reason: blocked);
      expect(find.byType(EditCustomerPage), findsNothing, reason: blocked);
    }
  });

  // ---------------------------------------------------------------------------
  // Role isolation across logout/login
  // ---------------------------------------------------------------------------

  // Checklist 11: admin → technician leaves nothing admin behind.
  testWidgets('admin logout → technician login: admin navigation disappears', (
    tester,
  ) async {
    await app.configure(user: adminUser, withCustomers: true);
    await seedCustomer('Alice Customer');
    await app.pump(tester);

    // Admin session with the Customers screen actually open.
    await tester.tap(find.byKey(const Key('nav_customers')));
    await tester.pumpAndSettle();
    expect(find.byType(CustomersPage), findsOneWidget);
    expect(find.text('Alice Customer'), findsOneWidget);

    // Back to the dashboard, then sign out and in as the technician.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await signOutFromHome(tester);
    await signInAs(tester, technicianUser);

    expect(find.byType(TechnicianHomePage), findsOneWidget);
    expect(find.byType(AdminHomePage), findsNothing);
    expect(find.byType(CustomersPage), findsNothing);
    expect(find.byKey(const Key('nav_customers')), findsNothing);
    expect(find.text('Alice Customer'), findsNothing);

    // The guard still refuses direct URLs in the new session.
    app.router.go(AppRoutes.customers);
    await tester.pumpAndSettle();
    expect(find.byType(CustomersPage), findsNothing);
    expect(find.byType(TechnicianHomePage), findsOneWidget);
  });

  // Checklist 12: technician → admin makes Customers available.
  testWidgets('technician logout → admin login: customers becomes reachable', (
    tester,
  ) async {
    await app.configure(
      user: technicianUser,
      withCustomers: true,
      jobs: <Job>[_job(id: 'job-1', number: 101)],
    );
    await seedCustomer('Alice Customer');
    await app.pump(tester);
    expect(find.byType(TechnicianHomePage), findsOneWidget);

    await signOutFromHome(tester);
    await signInAs(tester, adminUser);

    expect(find.byType(AdminHomePage), findsOneWidget);
    expect(find.byType(TechnicianHomePage), findsNothing);
    expect(find.byKey(const Key('nav_customers')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_customers')));
    await tester.pumpAndSettle();
    expect(find.byType(CustomersPage), findsOneWidget);
    expect(find.text('Alice Customer'), findsOneWidget);

    // End back on the dashboard (Drift-backed screens must close inside
    // the test body so their stream-cleanup timers can fire).
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(AdminHomePage), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Workflow regression through the navigation entry point
  // ---------------------------------------------------------------------------

  // Checklists 13–15: from the nav tile through Start Job to Before Photos.
  testWidgets('navigation keeps the full technician workflow intact', (
    tester,
  ) async {
    await tallSurface(tester);
    final File photo = writeTempPhoto(tempDir, 'before1.jpg');
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
    );
    await sl.unregister<PhotoPicker>();
    sl.registerSingleton<PhotoPicker>(_CameraPicker(<String>[photo.path]));
    await app.pump(tester);

    // Home → Jobs → Job Details via the navigation tile.
    await tester.tap(find.byKey(const Key('nav_jobs')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#101'));
    await tester.pumpAndSettle();
    expect(find.byType(JobDetailsPage), findsOneWidget);

    // Start Job flips the same screen into the in-progress workflow.
    await tester.tap(find.byKey(const Key('start_job_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('start_job_button')), findsNothing);
    final BuildContext detailsContext = tester.element(
      find.byType(JobDetailsPage),
    );
    expect(
      find.text(
        detailsContext.l10n.jobStartedAt(
          formatJobDate(serverStartedAt, detailsContext),
        ),
      ),
      findsOneWidget,
    );

    // Before Photos became available — capture still works end-to-end.
    expect(find.text('Before Photos'), findsOneWidget);
    expect(find.byKey(const Key('add_before_photo_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('add_before_photo_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('take_photo_option')));
    await tester.pumpAndSettle();

    expect(find.byType(BeforePhotoTile), findsOneWidget);
    expect(app.serverBeforePhotos['job-mine'], hasLength(1));
  });
}
