import 'dart:io';

import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/features/admin/presentation/pages/admin_home_page.dart';
import 'package:field_service/features/authentication/domain/entities/auth_session_event.dart';
import 'package:field_service/features/authentication/presentation/pages/login_page.dart';
import 'package:field_service/features/customers/data/datasources/customers_local_data_source.dart';
import 'package:field_service/features/customers/data/models/customer_model.dart';
import 'package:field_service/features/customers/domain/entities/customer_sync_status.dart';
import 'package:field_service/features/customers/presentation/pages/customers_page.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/pages/job_details_page.dart';
import 'package:field_service/features/jobs/presentation/pages/jobs_page.dart';
import 'package:field_service/features/jobs/presentation/services/photo_picker.dart';
import 'package:field_service/features/jobs/presentation/utils/jobs_date_format.dart';
import 'package:field_service/features/jobs/presentation/widgets/before_photo_tile.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_start_button.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_error_state.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_list_item.dart';
import 'package:field_service/features/technician/presentation/pages/technician_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';
import '../../support/test_photos.dart';

/// Integration tests: the already-implemented features (Job Details,
/// per-job customer info, Start Job + server `started_at`, Before Photos)
/// must be reachable as ONE connected technician workflow through the real
/// routes, pages, cubit and DI graph — no restarts, no re-login, no manual
/// reload between workflow steps.

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

/// Fake camera: serves one prepared file per pick.
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
    tempDir = Directory.systemTemp.createTempSync('workflow_integration');
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

  // ---------------------------------------------------------------------------
  // The connected workflow: Start Job → UI transitions → Before Photos.
  // Everything happens in ONE session on the same screen.
  // ---------------------------------------------------------------------------

  // Scenarios 7–12: the complete technician workflow end-to-end.
  testWidgets(
    'technician workflow: start → started time → before photos → capture',
    (tester) async {
      await tallSurface(tester);
      final File photo = writeTempPhoto(tempDir, 'before1.jpg');
      await app.configure(
        user: technicianUser,
        jobs: <Job>[_job(id: 'job-mine', number: 101)],
      );
      await sl.unregister<PhotoPicker>();
      sl.registerSingleton<PhotoPicker>(_CameraPicker(<String>[photo.path]));
      await app.pump(tester);

      // Login → Technician Home → View Jobs → Jobs List → Job Details.
      expect(find.byType(TechnicianHomePage), findsOneWidget);
      await tester.tap(find.text('View Jobs'));
      await tester.pumpAndSettle();
      expect(find.byType(JobsPage), findsOneWidget);
      await tester.tap(find.text('#101'));
      await tester.pumpAndSettle();
      expect(find.byType(JobDetailsPage), findsOneWidget);

      // ASSIGNED state: job info + customer info + Start Job,
      // and NO before-photo surface yet.
      expect(find.text('Job Information'), findsOneWidget);
      expect(find.byType(JobStartButton), findsOneWidget);
      expect(find.text('Before Photos'), findsNothing);
      expect(
        find.byKey(const Key('add_before_photo_button')),
        findsNothing,
      );

      // Start Job.
      await tester.tap(find.byKey(const Key('start_job_button')));
      await tester.pumpAndSettle();
      expect(find.text('Job started'), findsOneWidget);

      // The SAME screen transitions to the in-progress workflow:
      // button gone (the wrapper collapses to an empty box), in-progress
      // badge, started timestamp visible.
      expect(find.byKey(const Key('start_job_button')), findsNothing);
      expect(find.text('In Progress'), findsWidgets);
      final BuildContext detailsContext = tester.element(
        find.byType(JobDetailsPage),
      );
      final String expectedStarted = detailsContext.l10n.jobStartedAt(
        formatJobDate(serverStartedAt, detailsContext),
      );
      expect(find.text(expectedStarted), findsOneWidget);

      // Before Photos section + capture action became available —
      // without any restart or re-navigation.
      expect(find.text('Before Photos'), findsOneWidget);
      expect(find.byKey(const Key('add_before_photo_button')), findsOneWidget);
      expect(find.text('No before photos yet'), findsOneWidget);

      // Add Before Photo → camera → the photo appears inside Job Details.
      await tester.tap(find.byKey(const Key('add_before_photo_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('take_photo_option')));
      await tester.pumpAndSettle();

      expect(find.byType(BeforePhotoTile), findsOneWidget);
      expect(find.text('No before photos yet'), findsNothing);
      expect(app.serverBeforePhotos['job-mine'], hasLength(1));
      // The started timestamp is still the SERVER value after the capture.
      expect(find.text(expectedStarted), findsOneWidget);
    },
  );

  // Scenario 9: the visible started time is the server-generated one.
  testWidgets('started timestamp shown is the authoritative server value', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
    );
    await app.pump(tester);
    await tester.tap(find.text('View Jobs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#101'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start_job_button')));
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(find.byType(JobDetailsPage));
    // The fake server stamps `serverStartedAt` — the UI must show exactly
    // that value (a client-invented time would differ).
    expect(
      find.text(
        context.l10n.jobStartedAt(
          formatJobDate(serverStartedAt, context),
        ),
      ),
      findsOneWidget,
    );
    // The same value also feeds the Start Date field in Job Information.
    expect(find.text('Start Date'), findsWidgets);
  });

  // Scenario 6: Job Details → Back returns to the Jobs List cleanly.
  testWidgets('back navigation returns to the jobs list without duplicates', (
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
    await tester.tap(find.text('View Jobs'));
    await tester.pumpAndSettle();
    expect(find.byType(JobsListItem), findsNWidgets(2));

    await tester.tap(find.text('#101'));
    await tester.pumpAndSettle();
    expect(find.byType(JobDetailsPage), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // Exactly one list page, both rows intact — no duplicate cubit/page.
    expect(find.byType(JobsPage), findsOneWidget);
    expect(find.byType(JobDetailsPage), findsNothing);
    expect(find.byType(JobsListItem), findsNWidgets(2));

    // The list stays usable: the second job opens as well.
    await tester.tap(find.text('#102'));
    await tester.pumpAndSettle();
    expect(find.byType(JobDetailsPage), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Security matrix (compact integration copies; deep coverage lives in the
  // feature suites).
  // ---------------------------------------------------------------------------

  // Scenario 13: another technician's job is unreachable by URL.
  testWidgets('technician cannot open another technician\'s job', (
    tester,
  ) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
    );
    await app.pump(tester);

    app.router.go('/jobs/job-somebody-else');
    await tester.pumpAndSettle();

    // RLS mirror: the job is invisible → details fail closed, no data.
    expect(find.byType(JobsErrorState), findsOneWidget);
    expect(find.byType(JobStartButton), findsNothing);
    expect(find.text('Before Photos'), findsNothing);
  });

  // Scenario 14: technicians never reach the Customers area.
  testWidgets('technician is refused the customers route', (tester) async {
    await app.configure(
      user: technicianUser,
      withCustomers: true,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
    );
    await app.pump(tester);
    expect(find.byType(TechnicianHomePage), findsOneWidget);

    app.router.go(AppRoutes.customers);
    await tester.pumpAndSettle();

    expect(find.byType(CustomersPage), findsNothing);
    expect(find.byType(TechnicianHomePage), findsOneWidget);
  });

  // Scenarios 1–3 & 15: role switching never leaks the previous role's UI.
  testWidgets(
    'admin → logout → technician: no admin surface or customer data leaks',
    (tester) async {
      await tallSurface(tester);
      await app.configure(user: adminUser, withCustomers: true);
      // Seed the shared local customer mirror as the admin session.
      final CustomersLocalDataSource local = sl<CustomersLocalDataSource>();
      for (final String name in <String>['Alice Customer', 'Bob Customer']) {
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
      await app.pump(tester);

      // Admin session: Customers is open and shows data.
      expect(find.byType(AdminHomePage), findsOneWidget);
      await tester.tap(find.text('Customers'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomersPage), findsOneWidget);
      expect(find.text('Alice Customer'), findsOneWidget);

      // Logout → login screen.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sign Out'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);

      // Technician login: technician home, no admin surfaces anywhere.
      app.authentication.currentUser = technicianUser;
      app.authentication.events.add(AuthSessionEvent.signedIn);
      await tester.pumpAndSettle();
      expect(find.byType(TechnicianHomePage), findsOneWidget);
      expect(find.byType(AdminHomePage), findsNothing);
      expect(find.byType(CustomersPage), findsNothing);
      expect(find.text('Alice Customer'), findsNothing);

      // Even a direct URL to /customers stays refused.
      app.router.go(AppRoutes.customers);
      await tester.pumpAndSettle();
      expect(find.byType(CustomersPage), findsNothing);
      expect(find.byType(TechnicianHomePage), findsOneWidget);
    },
  );

  testWidgets('technician → logout → admin: admin navigation works', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      withCustomers: true,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
    );
    await app.pump(tester);
    expect(find.byType(TechnicianHomePage), findsOneWidget);
    await tester.tap(find.text('View Jobs'));
    await tester.pumpAndSettle();
    expect(find.byType(JobsPage), findsOneWidget);

    // Logout from a feature route, then log in as the admin.
    app.authentication.currentUser = null;
    app.authentication.events.add(AuthSessionEvent.signedOut);
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);

    app.authentication.currentUser = adminUser;
    app.authentication.events.add(AuthSessionEvent.signedIn);
    await tester.pumpAndSettle();

    // The admin lands in the admin area and reaches Customers.
    expect(find.byType(AdminHomePage), findsOneWidget);
    expect(find.byType(TechnicianHomePage), findsNothing);
    await tester.tap(find.text('Customers'));
    await tester.pumpAndSettle();
    expect(find.byType(CustomersPage), findsOneWidget);

    // Back out before the test ends: the Drift-backed customers cubit must
    // close inside the test body, where its stream-cleanup timer can fire.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(AdminHomePage), findsOneWidget);
  });
}
