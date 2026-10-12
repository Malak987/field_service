import 'package:field_service/features/admin/presentation/pages/admin_home_page.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/technician/presentation/pages/technician_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_test_harness.dart';
import '../support/test_authentication_repository.dart';

/// Locks the reorganized dashboards.
///
/// These are behaviour assertions about *what the screen says*, not about how
/// it is painted: the counts must come from the jobs that were actually loaded,
/// the recent-jobs list must be ordered by `updated_at` and capped, a failed
/// load must say so and offer a retry rather than showing a hole or a row of
/// confident zeros, and the tap targets the dashboards expose must stay
/// reachable.
void main() {
  late AppTestHarness app;
  setUp(() => app = AppTestHarness());
  tearDown(() => app.dispose());

  Job _job({
    required String id,
    required int number,
    JobStatus status = const JobStatus(JobStatus.assigned),
    String? technician = 'Omar Technician',
    DateTime? updatedAt,
  }) {
    final DateTime when = updatedAt ?? DateTime.utc(2026, 10, 1);
    return Job(
      id: id,
      jobNumber: number,
      customerId: 'cust-$id',
      customerName: 'Mina Customer',
      assignedEmployeeId: technician == null ? null : 'emp-1',
      assignedEmployeeName: technician,
      jobType: 'kitchen_renovation',
      description: 'Renovate the kitchen.',
      status: status,
      assignedAt: when,
      startedAt: null,
      createdAt: when,
      updatedAt: when,
      expiresAt: DateTime.utc(2026, 12, 1),
    );
  }

  /// The integer a stat tile renders.
  int statValue(WidgetTester tester, Key key) {
    final Iterable<Text> numbers = tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(key),
        matching: find.byType(Text),
      ),
    ).where((Text t) => RegExp(r'^\d+$').hasMatch(t.data ?? ''));
    expect(numbers, hasLength(1), reason: '$key must render exactly one number');
    return int.parse(numbers.single.data!);
  }

  group('admin dashboard overview', () {
    testWidgets('counts only the jobs that were loaded', (tester) async {
      await app.configure(
        user: adminUser,
        jobs: <Job>[
          _job(id: 'a', number: 101),
          _job(id: 'b', number: 102),
          _job(id: 'c', number: 103, status: const JobStatus(JobStatus.started)),
          _job(
            id: 'd',
            number: 104,
            status: const JobStatus(JobStatus.inProgress),
          ),
          _job(
            id: 'e',
            number: 105,
            status: const JobStatus(JobStatus.completed),
          ),
          _job(
            id: 'f',
            number: 106,
            status: const JobStatus(JobStatus.cancelled),
          ),
        ],
      );
      await app.pump(tester);
      await tester.pumpAndSettle();

      expect(statValue(tester, const Key('overview_total')), 6);
      expect(statValue(tester, const Key('overview_assigned')), 2);
      // `started` and `in_progress` are one bucket on the dashboard: both mean
      // begun-and-not-finished.
      expect(statValue(tester, const Key('overview_in_progress')), 2);
      expect(statValue(tester, const Key('overview_completed')), 1);
    });

    testWidgets('a failed load offers a retry instead of showing zeros', (
      tester,
    ) async {
      await app.configure(user: adminUser, jobsOffline: true);
      await app.pump(tester);
      await tester.pumpAndSettle();

      // No tile may claim a figure when nothing loaded.
      expect(find.byKey(const Key('overview_total')), findsNothing);
      // ...and the screen says so, with a way out.
      expect(find.byKey(const Key('overview_retry')), findsOneWidget);
      expect(find.byKey(const Key('recent_jobs_retry')), findsOneWidget);
    });
  });

  group('admin recent jobs', () {
    testWidgets('shows the five most recently updated, newest first', (
      tester,
    ) async {
      await app.configure(
        user: adminUser,
        jobs: <Job>[
          for (int i = 1; i <= 7; i++)
            _job(
              id: 'j$i',
              number: 100 + i,
              updatedAt: DateTime.utc(2026, 10, i),
            ),
        ],
      );
      await app.pump(tester);
      await tester.pumpAndSettle();

      // Tree order is visual order here: the rows are siblings in one Column.
      final List<String> shown = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((ListTile t) => (t.key as ValueKey<String>?)?.value ?? '')
          .where((String v) => v.startsWith('recent_job_'))
          .toList();

      expect(
        shown,
        <String>[
          'recent_job_j7',
          'recent_job_j6',
          'recent_job_j5',
          'recent_job_j4',
          'recent_job_j3',
        ],
        reason: 'newest updated_at first, capped at five',
      );
      expect(find.byKey(const Key('recent_job_j2')), findsNothing);
    });

    testWidgets('names the technician who holds the job', (tester) async {
      await app.configure(
        user: adminUser,
        jobs: <Job>[_job(id: 'held', number: 201)],
      );
      await app.pump(tester);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('recent_job_held')),
          matching: find.textContaining('Omar Technician'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an unassigned job says so rather than showing a blank', (
      tester,
    ) async {
      await app.configure(
        user: adminUser,
        jobs: <Job>[_job(id: 'free', number: 202, technician: null)],
      );
      await app.pump(tester);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('recent_job_free')),
          matching: find.textContaining('Unassigned'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('rows sit on a real ink surface', (tester) async {
      await app.configure(
        user: adminUser,
        jobs: <Job>[_job(id: 'ink', number: 203)],
      );
      await app.pump(tester);
      await tester.pumpAndSettle();

      final ThemeData theme = Theme.of(
        tester.element(find.byType(AdminHomePage)),
      );
      final Material? material = tester
          .element(find.byKey(const Key('recent_job_ink')))
          .findAncestorWidgetOfExactType<Material>();

      expect(material, isNotNull);
      expect(
        material!.color,
        theme.colorScheme.surface,
        reason:
            'the row must paint its splash on the white panel, not on the '
            'scaffold canvas behind it',
      );
    });

    testWidgets('an empty job list says so inside a surface', (tester) async {
      await app.configure(user: adminUser, jobs: const <Job>[]);
      await app.pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recent_jobs_empty')), findsOneWidget);
    });
  });

  group('dashboard chrome', () {
    testWidgets('both dashboards offer account & settings in the app bar', (
      tester,
    ) async {
      await app.configure(user: adminUser);
      await app.pump(tester);
      expect(find.byKey(const Key('nav_account')), findsOneWidget);
      expect(find.byType(AdminHomePage), findsOneWidget);
    });

    testWidgets('the technician dashboard offers it too', (tester) async {
      await app.configure(user: technicianUser);
      await app.pump(tester);
      expect(find.byType(TechnicianHomePage), findsOneWidget);
      expect(find.byKey(const Key('nav_account')), findsOneWidget);
      // Customer management stays admin-only: no entry may leak in here.
      expect(find.byKey(const Key('nav_customers')), findsNothing);
    });
  });

  group('technician dashboard', () {
    testWidgets('counts only the technician\'s own loaded jobs', (
      tester,
    ) async {
      await app.configure(
        user: technicianUser,
        jobs: <Job>[
          _job(id: 't1', number: 301),
          _job(
            id: 't2',
            number: 302,
            status: const JobStatus(JobStatus.inProgress),
          ),
          _job(
            id: 't3',
            number: 303,
            status: const JobStatus(JobStatus.completed),
          ),
        ],
      );
      await app.pump(tester);
      await tester.pumpAndSettle();

      expect(statValue(tester, const Key('tech_overview_total')), 3);
      expect(statValue(tester, const Key('tech_overview_assigned')), 1);
      expect(statValue(tester, const Key('tech_overview_in_progress')), 1);
      expect(statValue(tester, const Key('tech_overview_completed')), 1);
    });

    testWidgets('the featured job shows when it was assigned', (tester) async {
      await app.configure(
        user: technicianUser,
        jobs: <Job>[
          _job(
            id: 'run',
            number: 304,
            status: const JobStatus(JobStatus.inProgress),
            updatedAt: DateTime.utc(2026, 10, 4),
          ),
        ],
      );
      await app.pump(tester);
      await tester.pumpAndSettle();

      // The card must carry a date line at all — the exact wording is the
      // localized "Assigned Date" label, asserted loosely so a copy tweak does
      // not break the guarantee that a date is shown.
      expect(find.byKey(const Key('continue_job_run')), findsOneWidget);
      expect(find.textContaining('Assigned Date'), findsWidgets);
    });
  });
}
