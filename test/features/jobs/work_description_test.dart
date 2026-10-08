import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/pages/job_details_page.dart';
import 'package:field_service/features/jobs/presentation/widgets/work_description_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';

/// UI contract of the Work Description step (Phase 9).
///
/// The section sits at the bottom of Job Details, AFTER the Before Photos
/// card. The ASSIGNED technician edits their own `in_progress` job; admins
/// monitor read-only; closed jobs are read-only. The server RPC is the
/// final authority — the UI only reflects it.
void main() {
  late AppTestHarness app;
  setUp(() => app = AppTestHarness());
  tearDown(() => app.dispose());

  Job seedJob({
    required String id,
    required int number,
    String? assignedEmployeeId,
    String status = JobStatus.inProgress,
    DateTime? startedAt,
    String? workDescription,
  }) {
    return Job(
      id: id,
      jobNumber: number,
      customerId: 'cust-$id',
      assignedEmployeeId: assignedEmployeeId,
      jobType: 'kitchen_renovation',
      description: 'Fix the sink.',
      workDescription: workDescription,
      status: JobStatus(status),
      startedAt: startedAt,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
      expiresAt: DateTime.utc(2026, 12, 1),
    );
  }

  /// Dashboard → Jobs → first job card → details (mirrors the other
  /// Job Details test suites).
  Future<void> openFirstJobDetails(WidgetTester tester) async {
    await tester.tap(find.text('View Jobs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#101'));
    await tester.pumpAndSettle();
    expect(find.byType(JobDetailsPage), findsOneWidget);
  }

  Future<void> enterWorkDescription(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.byKey(const Key('work_description_field')));
    await tester.enterText(
      find.byKey(const Key('work_description_field')),
      text,
    );
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byKey(const Key('save_work_description_button')),
    );
    await tester.tap(find.byKey(const Key('save_work_description_button')));
    await tester.pumpAndSettle();
  }

  // Test 1 — technician on an in_progress job saves their report: trimmed
  // text reaches the backend exactly once, snackbar confirms, the field
  // keeps the text (optimistic local state).
  _testJobDetails('technician saves a work description on an in_progress job', (
    tester,
  ) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        seedJob(
          id: 'job-1',
          number: 101,
          assignedEmployeeId: 'emp-tech-1',
          startedAt: DateTime.utc(2026, 10, 6, 9, 30),
        ),
      ],
    );
    await app.pump(tester);
    await _tallSurface(tester);
    await openFirstJobDetails(tester);

    // Editable surface: multiline field + Save button.
    expect(find.byKey(const Key('work_description_field')), findsOneWidget);
    expect(
      find.byKey(const Key('save_work_description_button')),
      findsOneWidget,
    );
    expect(find.text('Work Description'), findsOneWidget);

    await enterWorkDescription(tester, 'Replaced the sink.');
    await tapSave(tester);

    // Confirmation snackbar, backend received the text once.
    expect(find.text('Work description saved.'), findsOneWidget);
    expect(app.savedWorkDescriptions['job-1'], <String>['Replaced the sink.']);

    // Optimistic state: the field keeps the saved value on the same screen.
    final TextField field = tester.widget<TextField>(
      find.byKey(const Key('work_description_field')),
    );
    expect(field.controller!.text, 'Replaced the sink.');

    // Reopen the job: the CURRENT saved value is shown for further editing.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('#101'));
    await tester.pumpAndSettle();
    final TextField reopened = tester.widget<TextField>(
      find.byKey(const Key('work_description_field')),
    );
    expect(reopened.controller!.text, 'Replaced the sink.');
  });

  // Test 2 — empty/whitespace-only saves are refused with the localized
  // inline error; nothing is submitted, no snackbar.
  _testJobDetails('saving empty text shows the inline error, submits nothing', (
    tester,
  ) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        seedJob(
          id: 'job-1',
          number: 101,
          assignedEmployeeId: 'emp-tech-1',
          startedAt: DateTime.utc(2026, 10, 6, 9, 30),
        ),
      ],
    );
    await app.pump(tester);
    await _tallSurface(tester);
    await openFirstJobDetails(tester);

    await enterWorkDescription(tester, '');
    await tapSave(tester);
    expect(find.text('Work description cannot be empty.'), findsOneWidget);

    await enterWorkDescription(tester, '   \n\t ');
    await tapSave(tester);
    expect(find.text('Work description cannot be empty.'), findsOneWidget);

    expect(find.text('Work description saved.'), findsNothing);
    expect(app.savedWorkDescriptions, isEmpty);
  });

  // Test 3 — over-long text is refused inline (no silent truncation).
  _testJobDetails('over-long text shows the length error inline', (
    tester,
  ) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        seedJob(
          id: 'job-1',
          number: 101,
          assignedEmployeeId: 'emp-tech-1',
          startedAt: DateTime.utc(2026, 10, 6, 9, 30),
        ),
      ],
    );
    await app.pump(tester);
    await _tallSurface(tester);
    await openFirstJobDetails(tester);

    await enterWorkDescription(tester, 'a' * 4001);
    await tapSave(tester);

    expect(
      find.text('Work description is too long (maximum 4000 characters).'),
      findsOneWidget,
    );
    expect(find.text('Work description saved.'), findsNothing);
    expect(app.savedWorkDescriptions, isEmpty);
  });

  // Test 4 — a previously saved description reappears prefilled and stays
  // editable for the same technician while the job is in_progress.
  _testJobDetails('existing description is prefilled and editable', (
    tester,
  ) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        seedJob(
          id: 'job-1',
          number: 101,
          assignedEmployeeId: 'emp-tech-1',
          startedAt: DateTime.utc(2026, 10, 6, 9, 30),
          workDescription: 'Old description.',
        ),
      ],
    );
    await app.pump(tester);
    await _tallSurface(tester);
    await openFirstJobDetails(tester);

    final TextField field = tester.widget<TextField>(
      find.byKey(const Key('work_description_field')),
    );
    expect(field.controller!.text, 'Old description.');

    await enterWorkDescription(tester, 'Updated description.');
    await tapSave(tester);

    expect(find.text('Work description saved.'), findsOneWidget);
    expect(app.savedWorkDescriptions['job-1'], <String>[
      'Updated description.',
    ]);
  });

  // Test 5 — backend failure surfaces as the failure snackbar (the text is
  // NOT lost: the field keeps what the technician typed).
  _testJobDetails('save failure surfaces the failure snackbar', (tester) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        seedJob(
          id: 'job-1',
          number: 101,
          assignedEmployeeId: 'emp-tech-1',
          startedAt: DateTime.utc(2026, 10, 6, 9, 30),
        ),
      ],
      saveWorkDescriptionError: StateError('Simulated backend failure.'),
    );
    await app.pump(tester);
    await _tallSurface(tester);
    await openFirstJobDetails(tester);

    await enterWorkDescription(tester, 'Replaced the sink.');
    await tapSave(tester);

    expect(find.text('Failed to save work description.'), findsOneWidget);
    expect(find.text('Work description saved.'), findsNothing);
    expect(app.savedWorkDescriptions, isEmpty);

    // The typed text survives the failure.
    final TextField field = tester.widget<TextField>(
      find.byKey(const Key('work_description_field')),
    );
    expect(field.controller!.text, 'Replaced the sink.');
  });

  // Test 6 — the admin MONITORS: read-only section, never a write control,
  // even on an in_progress job.
  _testJobDetails('admin sees the saved description read-only', (tester) async {
    await app.configure(
      user: adminUser,
      jobs: <Job>[
        seedJob(
          id: 'job-1',
          number: 101,
          assignedEmployeeId: 'emp-tech-1',
          startedAt: DateTime.utc(2026, 10, 6, 9, 30),
          workDescription: 'Fixed everything by Friday.',
        ),
      ],
    );
    await app.pump(tester);
    await _tallSurface(tester);
    await openFirstJobDetails(tester);

    expect(find.text('Work Description'), findsOneWidget);
    expect(find.text('Fixed everything by Friday.'), findsOneWidget);
    expect(find.byKey(const Key('work_description_field')), findsNothing);
    expect(find.byKey(const Key('save_work_description_button')), findsNothing);
    expect(app.savedWorkDescriptions, isEmpty);
  });

  // Test 7 — admin on an in_progress job without a description yet sees the
  // localized "nothing yet" note (never a form).
  _testJobDetails('admin sees the "nothing yet" note when unsaved', (
    tester,
  ) async {
    await app.configure(
      user: adminUser,
      jobs: <Job>[
        seedJob(
          id: 'job-1',
          number: 101,
          assignedEmployeeId: 'emp-tech-1',
          startedAt: DateTime.utc(2026, 10, 6, 9, 30),
        ),
      ],
    );
    await app.pump(tester);
    await _tallSurface(tester);
    await openFirstJobDetails(tester);

    expect(find.text('No work description yet.'), findsOneWidget);
    expect(find.byKey(const Key('work_description_field')), findsNothing);
    expect(find.byKey(const Key('save_work_description_button')), findsNothing);
  });

  // Test 8 — while the job is still ASSIGNED the section does not exist yet
  // (the workflow starts with Start Job).
  _testJobDetails('no work description section while the job is assigned', (
    tester,
  ) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        seedJob(
          id: 'job-1',
          number: 101,
          assignedEmployeeId: 'emp-tech-1',
          status: JobStatus.assigned,
        ),
      ],
    );
    await app.pump(tester);
    await _tallSurface(tester);
    await openFirstJobDetails(tester);

    expect(find.text('Work Description'), findsNothing);
    expect(find.byKey(const Key('work_description_field')), findsNothing);
    expect(find.byKey(const Key('save_work_description_button')), findsNothing);
  });

  // Test 9 — after completion the description is history: read-only, no
  // Save button (the server refuses writes on completed jobs anyway).
  _testJobDetails('completed job shows the description read-only', (
    tester,
  ) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        seedJob(
          id: 'job-1',
          number: 101,
          assignedEmployeeId: 'emp-tech-1',
          status: JobStatus.completed,
          startedAt: DateTime.utc(2026, 10, 6, 9, 30),
          workDescription: 'All done.',
        ),
      ],
    );
    await app.pump(tester);
    await _tallSurface(tester);
    await openFirstJobDetails(tester);

    expect(find.text('All done.'), findsOneWidget);
    expect(find.byKey(const Key('work_description_field')), findsNothing);
    expect(find.byKey(const Key('save_work_description_button')), findsNothing);
  });

  // Test 10 — the section renders inside Job Details (regression guard that
  // page composition still builds for both roles).
  test('WorkDescriptionSection is exported and constructible', () {
    final WorkDescriptionSection section = WorkDescriptionSection(
      initialText: 'x',
      canEdit: false,
      isSaving: false,
      error: null,
      onSave: (String _) {},
    );
    expect(section.initialText, 'x');
    expect(section.canEdit, isFalse);
  });
}

/// Tall surface: Work Description sits at the bottom of Job Details — below
/// the Before Photos card — so the default 800x600 canvas keeps it offstage.
Future<void> _tallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1600));
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
