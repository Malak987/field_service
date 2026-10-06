import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/features/admin/presentation/pages/admin_home_page.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/features/jobs/presentation/pages/job_details_page.dart';
import 'package:field_service/features/jobs/presentation/utils/jobs_date_format.dart';
import 'package:field_service/features/jobs/presentation/pages/jobs_page.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_start_button.dart';
import 'package:field_service/features/technician/presentation/pages/technician_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';

/// Builds a job in the given [status]; `startedAt` is only set for jobs the
/// "server" has already started (client code never invents one).
Job _job({
  required String id,
  required int number,
  String? assignedEmployeeId,
  String status = JobStatus.assigned,
  DateTime? startedAt,
}) {
  return Job(
    id: id,
    jobNumber: number,
    customerId: 'cust-$id',
    assignedEmployeeId: assignedEmployeeId,
    jobType: 'maintenance',
    description: 'Fix the sink.',
    status: JobStatus(status),
    startedAt: startedAt,
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
    expiresAt: DateTime.utc(2026, 12, 1),
  );
}

void main() {
  late AppTestHarness app;
  setUp(() => app = AppTestHarness());
  tearDown(() => app.dispose());

  /// Dashboard → Jobs → first job card → details.
  Future<void> openFirstJobDetails(WidgetTester tester) async {
    await tester.tap(find.text('View Jobs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#101'));
    await tester.pumpAndSettle();
    expect(find.byType(JobDetailsPage), findsOneWidget);
  }

  // Test 1 / 12 — admin can start; UI flips to in_progress immediately.
  testWidgets('admin can start a job and the UI reflects in_progress', (
    tester,
  ) async {
    await app.configure(
      user: adminUser,
      jobs: <Job>[
        _job(id: 'job-1', number: 101, assignedEmployeeId: 'emp-tech-1'),
      ],
    );
    await app.pump(tester);
    expect(find.byType(AdminHomePage), findsOneWidget);
    await openFirstJobDetails(tester);

    // Start Job is offered exactly while the job is `assigned`.
    expect(find.byType(JobStartButton), findsOneWidget);
    expect(find.byKey(const Key('start_job_button')), findsOneWidget);
    expect(find.text('Assigned'), findsWidgets);

    await tester.tap(find.byKey(const Key('start_job_button')));
    await tester.pumpAndSettle();

    expect(find.text('Job started'), findsOneWidget); // snackbar
    expect(find.text('In Progress'), findsWidgets); // badge + status field
    expect(find.byKey(const Key('start_job_button')), findsNothing);
    expect(find.text('Assigned'), findsNothing);
    expect(app.startedJobIds, <String>['job-1']);
  });

  // Test 2 / 12 — technician can start their own assigned job.
  testWidgets('technician can start their own assigned job', (tester) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(id: 'job-1', number: 101, assignedEmployeeId: 'emp-tech-1'),
      ],
    );
    await app.pump(tester);
    expect(find.byType(TechnicianHomePage), findsOneWidget);
    await openFirstJobDetails(tester);

    await tester.tap(find.byKey(const Key('start_job_button')));
    await tester.pumpAndSettle();

    expect(find.text('Job started'), findsOneWidget);
    expect(find.text('In Progress'), findsWidgets);
    expect(find.byKey(const Key('start_job_button')), findsNothing);
    expect(app.startedJobIds, <String>['job-1']);
  });

  // Test 3 — server refuses another technician's job: nothing changes.
  testWidgets('technician cannot start another technician\'s job', (
    tester,
  ) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(id: 'job-1', number: 101, assignedEmployeeId: 'emp-tech-1'),
      ],
      startJobError: StateError('This job is not assigned to you.'),
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    await tester.tap(find.byKey(const Key('start_job_button')));
    await tester.pumpAndSettle();

    expect(find.text('Unable to start job'), findsOneWidget);
    expect(find.text('Assigned'), findsWidgets); // unchanged
    expect(find.text('In Progress'), findsNothing);
    expect(find.text('Start Date'), findsNothing);
    expect(app.startedJobIds, isEmpty);
  });

  // Test 4 — an unassigned job cannot be started.
  testWidgets('technician cannot start an unassigned job', (tester) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-1', number: 101)], // no assignedEmployeeId
      startJobError: StateError('This job is not assigned to you.'),
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    await tester.tap(find.byKey(const Key('start_job_button')));
    await tester.pumpAndSettle();

    expect(find.text('Unable to start job'), findsOneWidget);
    expect(find.text('Assigned'), findsWidgets);
    expect(app.startedJobIds, isEmpty);
  });

  // Test 5 — an inactive employee account cannot start a job.
  testWidgets('inactive technician cannot start a job', (tester) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(id: 'job-1', number: 101, assignedEmployeeId: 'emp-tech-1'),
      ],
      startJobError: StateError('No active employee is linked to this account.'),
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    await tester.tap(find.byKey(const Key('start_job_button')));
    await tester.pumpAndSettle();

    expect(find.text('Unable to start job'), findsOneWidget);
    expect(find.text('Assigned'), findsWidgets);
    expect(app.startedJobIds, isEmpty);
  });

  // Test 6a — an already-started job offers no Start button at all.
  testWidgets('already-started job shows no Start button', (tester) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(
          id: 'job-1',
          number: 101,
          assignedEmployeeId: 'emp-tech-1',
          status: JobStatus.inProgress,
          startedAt: DateTime.utc(2026, 10, 6, 9, 30),
        ),
      ],
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    expect(find.byKey(const Key('start_job_button')), findsNothing);
    expect(find.text('In Progress'), findsWidgets);
    expect(find.text('Start Date'), findsOneWidget); // server timestamp shown
    expect(app.startedJobIds, isEmpty);
  });

  // Test 6b — duplicate-start guard: the queued/known start blocks a second.
  testWidgets('a second start attempt is rejected as already started', (
    tester,
  ) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(id: 'job-1', number: 101, assignedEmployeeId: 'emp-tech-1'),
      ],
      alreadyStartedJobIds: const <String>{'job-1'},
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    await tester.tap(find.byKey(const Key('start_job_button')));
    await tester.pumpAndSettle();

    expect(find.text('Job has already been started'), findsOneWidget);
    expect(find.text('Assigned'), findsWidgets); // nothing was re-applied
    expect(app.startedJobIds, isEmpty);
  });

  // Test 7 — no client timestamp: the visible started time is always the
  // server-generated one. Since the integration phase the details screen
  // fetches the authoritative row right after the start, so the server value
  // appears on the same screen — but it is still `serverStartedAt` stamped
  // by the fake server, never a client-invented time.
  testWidgets('started_at is automatic and server-authoritative', (
    tester,
  ) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(id: 'job-1', number: 101, assignedEmployeeId: 'emp-tech-1'),
      ],
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);
    expect(find.text('Start Date'), findsNothing);

    await tester.tap(find.byKey(const Key('start_job_button')));
    await tester.pumpAndSettle();

    // in_progress, with the authoritative started_at fetched from the
    // server row (a client-invented time would differ from serverStartedAt).
    expect(find.text('In Progress'), findsWidgets);
    expect(find.text('Start Date'), findsOneWidget);
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

    // Re-open the job: the server row still carries the same started_at.
    app.router.go(AppRoutes.jobs);
    await tester.pumpAndSettle();
    expect(find.byType(JobsPage), findsOneWidget);
    await tester.tap(find.text('#101'));
    await tester.pumpAndSettle();
    expect(find.byType(JobDetailsPage), findsOneWidget);
    expect(find.text('Start Date'), findsOneWidget);
    expect(find.byKey(const Key('start_job_button')), findsNothing);
  });

  // Test 11 — Start Job is only offered for `assigned` jobs.
  testWidgets('completed jobs offer no Start button', (tester) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(
          id: 'job-1',
          number: 101,
          assignedEmployeeId: 'emp-tech-1',
          status: JobStatus.completed,
          startedAt: DateTime.utc(2026, 10, 1, 8),
        ),
      ],
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    expect(find.byKey(const Key('start_job_button')), findsNothing);
    expect(find.text('Completed'), findsWidgets);
  });

  // Test 11/12 companion — the jobs list itself reflects the flip.
  testWidgets('jobs list reflects in_progress after starting', (tester) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(id: 'job-1', number: 101, assignedEmployeeId: 'emp-tech-1'),
      ],
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);
    await tester.tap(find.byKey(const Key('start_job_button')));
    await tester.pumpAndSettle();

    // The list page below the details keeps its own cubit (existing
    // architecture — the jobs list reloads on refresh/next visit), so
    // assert the flip on the next fresh list load.
    app.router.go(AppRoutes.root);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View Jobs'));
    await tester.pumpAndSettle();
    expect(find.text('In Progress'), findsOneWidget); // list badge
    expect(find.text('Assigned'), findsNothing);
  });
}
