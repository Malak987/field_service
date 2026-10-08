import 'package:field_service/features/admin/presentation/pages/admin_home_page.dart';
import 'package:field_service/features/authentication/presentation/pages/account_page.dart';
import 'package:field_service/features/authentication/presentation/pages/login_page.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/pages/job_details_page.dart';
import 'package:field_service/features/jobs/presentation/pages/jobs_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_test_harness.dart';
import '../support/test_authentication_repository.dart';

/// Round-8 UI/UX tests: role-aware home dashboards, bottom navigation,
/// category shortcuts and the account screen.
///
/// Everything asserted here is REAL data through the existing cubits and
/// router — no fakes are injected into the UI, no business behaviour is
/// altered.

Job _job({
  required String id,
  required int number,
  String status = JobStatus.assigned,
  String jobType = 'kitchen_renovation',
  String? customerName,
}) {
  return Job(
    id: id,
    jobNumber: number,
    customerId: 'cust-$id',
    customerName: customerName,
    assignedEmployeeId: 'emp-tech-1',
    jobType: jobType,
    description: 'Renovate the kitchen.',
    status: JobStatus(status),
    startedAt: null,
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
    expiresAt: DateTime.utc(2026, 12, 1),
  );
}

void main() {
  late AppTestHarness app;

  setUp(() => app = AppTestHarness());
  tearDown(() => app.dispose());

  // ---------------------------------------------------------------------------
  // Admin home dashboard
  // ---------------------------------------------------------------------------

  testWidgets('admin home shows the 4-item bottom nav', (tester) async {
    await app.configure(user: adminUser);
    await app.pump(tester);

    expect(find.byType(AdminHomePage), findsOneWidget);
    expect(find.byKey(const Key('bottom_nav_home')), findsOneWidget);
    expect(find.byKey(const Key('bottom_nav_kitchen')), findsOneWidget);
    expect(find.byKey(const Key('bottom_nav_home_renovation')), findsOneWidget);
    expect(find.byKey(const Key('bottom_nav_account')), findsOneWidget);
    // The technician's extra tab must not leak into the admin bar.
    expect(find.byKey(const Key('bottom_nav_my_jobs')), findsNothing);
  });

  testWidgets('admin overview shows only real counts from loaded jobs', (
    tester,
  ) async {
    await app.configure(
      user: adminUser,
      jobs: <Job>[
        _job(id: 'job-1', number: 101),
        _job(id: 'job-2', number: 102, status: JobStatus.inProgress),
        _job(id: 'job-3', number: 103, status: JobStatus.completed),
      ],
    );
    await app.pump(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('overview_assigned')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('overview_assigned')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('overview_in_progress')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('overview_completed')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('kitchen category card opens the filtered jobs list', (
    tester,
  ) async {
    await app.configure(
      user: adminUser,
      jobs: <Job>[
        _job(id: 'job-1', number: 101),
        _job(id: 'job-2', number: 102, jobType: 'home_renovation'),
      ],
    );
    await app.pump(tester);
    await tester.pumpAndSettle();

    // The category card shows the REAL per-category count.
    expect(
      find.descendant(
        of: find.byKey(const Key('category_card_kitchen')),
        matching: find.text('1 job'),
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byKey(const Key('category_card_kitchen')));
    await tester.tap(find.byKey(const Key('category_card_kitchen')));
    await tester.pumpAndSettle();

    expect(find.byType(JobsPage), findsOneWidget);
    expect(find.text('#101'), findsOneWidget);
    expect(find.text('#102'), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // Technician home
  // ---------------------------------------------------------------------------

  testWidgets('technician home shows a professional empty state', (
    tester,
  ) async {
    await app.configure(user: technicianUser);
    await app.pump(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tech_jobs_empty')), findsOneWidget);
    expect(find.text('No assigned jobs'), findsOneWidget);
    expect(
      find.text('New jobs assigned to you will appear here.'),
      findsOneWidget,
    );
    // Customer management never appears for technicians.
    expect(find.byKey(const Key('nav_customers')), findsNothing);
    expect(find.text('Customers'), findsNothing);
  });

  testWidgets('technician home features the in-progress job', (tester) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(
          id: 'job-run',
          number: 101,
          status: JobStatus.inProgress,
          customerName: 'Anna Customer',
        ),
        _job(id: 'job-wait', number: 102),
      ],
    );
    await app.pump(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('continue_job_job-run')), findsOneWidget);
    expect(find.text('Anna Customer'), findsOneWidget);
    expect(find.text('Continue Job'), findsOneWidget);

    await tester.tap(find.byKey(const Key('continue_job_job-run')));
    await tester.pumpAndSettle();
    expect(find.byType(JobDetailsPage), findsOneWidget);
  });

  testWidgets('technician bottom nav has 3 destinations and no admin tabs', (
    tester,
  ) async {
    await app.configure(user: technicianUser);
    await app.pump(tester);

    expect(find.byKey(const Key('bottom_nav_home')), findsOneWidget);
    expect(find.byKey(const Key('bottom_nav_my_jobs')), findsOneWidget);
    expect(find.byKey(const Key('bottom_nav_account')), findsOneWidget);
    expect(find.byKey(const Key('bottom_nav_kitchen')), findsNothing);
    expect(find.byKey(const Key('bottom_nav_home_renovation')), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // Account screen (both roles)
  // ---------------------------------------------------------------------------

  testWidgets('admin reaches the account screen and can sign out', (
    tester,
  ) async {
    await app.configure(user: adminUser);
    await app.pump(tester);

    await tester.tap(find.byKey(const Key('bottom_nav_account')));
    await tester.pumpAndSettle();

    expect(find.byType(AccountPage), findsOneWidget);
    expect(find.byKey(const Key('account_avatar')), findsOneWidget);
    expect(find.text('admin@example.com'), findsOneWidget);
    expect(find.text('Administrator'), findsOneWidget);

    await tester.tap(find.byKey(const Key('account_sign_out')));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('technician account shows the technician role', (tester) async {
    await app.configure(user: technicianUser);
    await app.pump(tester);

    await tester.tap(find.byKey(const Key('bottom_nav_account')));
    await tester.pumpAndSettle();

    expect(find.byType(AccountPage), findsOneWidget);
    expect(find.text('technician@example.com'), findsOneWidget);
    expect(find.text('Technician'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Bottom navigation behaviour
  // ---------------------------------------------------------------------------

  testWidgets('bottom nav never stacks pages on repeated taps', (tester) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-1', number: 101)],
    );
    await app.pump(tester);

    await tester.tap(find.byKey(const Key('bottom_nav_my_jobs')));
    await tester.pump();
    if (find.byKey(const Key('bottom_nav_my_jobs')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('bottom_nav_my_jobs')));
    }
    await tester.pumpAndSettle();

    expect(find.byType(JobsPage), findsOneWidget);
  });
}
