import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/pages/job_details_page.dart';
import 'package:field_service/features/jobs/presentation/widgets/complete_job_section.dart';
import 'package:field_service/features/jobs/presentation/widgets/signature_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';

/// UI tests for Complete Job — the FINAL workflow step — against the fake
/// jobs repository (which mirrors the `complete_job` RPC's server-side
/// rules: technician-only, ownership, `in_progress`, the four server-queried
/// completion conditions, server `completed_at`, exactly one
/// `job_completed` event).
///
/// The checklist the section renders is CLIENT knowledge only — every test
/// that completes a job does so through the fake server, and refusal paths
/// prove the UI surfaces the server's verdict.

Job _job({
  required String id,
  required int number,
  String? assignedEmployeeId = 'emp-tech-1',
  String status = JobStatus.inProgress,
  String? workDescription = 'Replaced the sink.',
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
    startedAt: status == JobStatus.assigned ? null : DateTime.utc(2026, 9, 2),
    completedAt: status == JobStatus.completed
        ? DateTime.utc(2026, 9, 3, 17)
        : null,
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
    expiresAt: DateTime.utc(2026, 12, 1),
  );
}

JobFile _file(
  String id,
  String jobId,
  String fileType, {
  JobFileSyncState syncState = JobFileSyncState.synced,
}) {
  return JobFile(
    id: id,
    jobId: jobId,
    fileType: fileType,
    fileName: '$id.jpg',
    mimeType: fileType == 'signature' ? 'image/png' : 'image/jpeg',
    capturedAt: DateTime.utc(2026, 9, 2, 12),
    // A pending file has no confirmed remote path yet — exactly like a real
    // local row awaiting its upload.
    remotePath: syncState == JobFileSyncState.synced
        ? 'jobs/$jobId/$fileType/$id.jpg'
        : null,
    syncState: syncState,
  );
}

void main() {
  late AppTestHarness app;

  setUp(() => app = AppTestHarness());
  tearDown(() => app.dispose());

  /// Job Details stacks many cards; the Complete Job section sits lowest.
  Future<void> tallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 3300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  /// Dashboard → Jobs → first job card → details.
  Future<void> openFirstJobDetails(WidgetTester tester) async {
    await tester.tap(find.text('View Jobs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#101'));
    await tester.pumpAndSettle();
    expect(find.byType(JobDetailsPage), findsOneWidget);
  }

  /// Configures a job where the CLIENT knows of all four requirements.
  ///
  /// [unsyncedType] captures that file kind locally WITHOUT a confirmed
  /// upload (`syncState: pending`) — mirroring a file still sitting in the
  /// sync queue, invisible to the server.
  Future<void> configureCompleteable({
    AppUser user = technicianUser,
    Job? job,
    bool completionOffline = false,
    Set<String> photoDeniedJobIds = const <String>{},
    String? unsyncedType,
  }) {
    final Job effectiveJob = job ?? _job(id: 'job-mine', number: 101);

    JobFile fileOf(String type) {
      return _file(
        '$type-1',
        effectiveJob.id,
        type,
        syncState: unsyncedType == type
            ? JobFileSyncState.pending
            : JobFileSyncState.synced,
      );
    }

    return app.configure(
      user: user,
      jobs: <Job>[effectiveJob],
      photoDeniedJobIds: photoDeniedJobIds,
      completionOffline: completionOffline,
      initialBeforePhotos: <String, List<JobFile>>{
        effectiveJob.id: <JobFile>[fileOf('before')],
      },
      initialAfterPhotos: <String, List<JobFile>>{
        effectiveJob.id: <JobFile>[fileOf('after')],
      },
      initialSignatures: <String, List<JobFile>>{
        effectiveJob.id: <JobFile>[
          _file(
            'sig-1',
            effectiveJob.id,
            'signature',
            syncState: unsyncedType == 'signature'
                ? JobFileSyncState.pending
                : JobFileSyncState.synced,
          ),
        ],
      },
    );
  }

  // 1 — the section renders AFTER Customer Signature with all four
  // requirement rows checked and an enabled button.
  testWidgets('the complete section shows the full checklist', (tester) async {
    await tallSurface(tester);
    await configureCompleteable();
    await app.pump(tester);
    await openFirstJobDetails(tester);
    await tester.pump();

    expect(find.text('Complete Job'), findsWidgets); // title + button
    expect(find.text('Completion Requirements'), findsOneWidget);
    expect(
      find.byKey(const Key('completion_requirement_before_photos')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('completion_requirement_work_description')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('completion_requirement_after_photos')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('completion_requirement_customer_signature')),
      findsOneWidget,
    );
    // All four known-met → four check marks, zero open circles (scoped to
    // the section: the photo tiles use a similar check icon for synced).
    final Finder section = find.byType(CompleteJobSection);
    expect(
      find.descendant(
        of: section,
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsNWidgets(4),
    );
    expect(
      find.descendant(
        of: section,
        matching: find.byIcon(Icons.radio_button_unchecked_rounded),
      ),
      findsNothing,
    );

    final FilledButton button = tester.widget<FilledButton>(
      find.byKey(const Key('complete_job_button')),
    );
    expect(button.enabled, isTrue);

    // Placement: below the Customer Signature card (scoped to the section
    // title — the checklist row repeats the same label).
    final double signatureDy = tester
        .getTopLeft(
          find.descendant(
            of: find.byType(SignatureSection),
            matching: find.text('Customer Signature'),
          ),
        )
        .dy;
    final double completeDy = tester
        .getTopLeft(find.text('Completion Requirements'))
        .dy;
    expect(completeDy, greaterThan(signatureDy));
  });

  // 2 — a missing requirement is shown unchecked and disables the button.
  testWidgets('a missing requirement disables the button', (tester) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
      initialBeforePhotos: <String, List<JobFile>>{
        'job-mine': <JobFile>[_file('before-1', 'job-mine', 'before')],
      },
      // No after photos, no signature yet.
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);
    await tester.pump();

    final Finder section = find.byType(CompleteJobSection);
    expect(
      find.descendant(
        of: section,
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: section,
        matching: find.byIcon(Icons.radio_button_unchecked_rounded),
      ),
      findsNWidgets(2),
    );

    final FilledButton button = tester.widget<FilledButton>(
      find.byKey(const Key('complete_job_button')),
    );
    expect(button.enabled, isFalse);
    expect(app.completedJobIds, isEmpty);
  });

  // 3 — a successful completion: server-confirmed status, server
  // timestamp, read-only page, no workflow mutation left.
  testWidgets('tapping Complete Job finishes the job via the server', (
    tester,
  ) async {
    await tallSurface(tester);
    await configureCompleteable();
    await app.pump(tester);
    await openFirstJobDetails(tester);
    await tester.pump();

    await tester.tap(find.byKey(const Key('complete_job_button')));
    await tester.pumpAndSettle();

    // Success feedback + exactly one server-accepted completion.
    expect(find.text('Job completed'), findsOneWidget);
    expect(app.completedJobIds, <String>['job-mine']);
    expect(app.jobCompletedEvents, hasLength(1));
    expect(app.jobCompletedEvents.single['event_type'], 'job_completed');
    expect(app.jobCompletedEvents.single['occurred_at'], serverCompletedAt);

    // The completion section is gone — the job is no longer in_progress…
    expect(find.byKey(const Key('complete_job_button')), findsNothing);
    expect(find.text('Completion Requirements'), findsNothing);

    // …and the completed state is shown with the SERVER timestamp.
    expect(find.text('Completed'), findsWidgets); // status badge + field
    expect(find.text('Completed Date'), findsOneWidget);

    // No technician workflow mutation remains available.
    expect(find.byKey(const Key('start_job_button')), findsNothing);
    expect(find.byKey(const Key('add_before_photo_button')), findsNothing);
    expect(find.byKey(const Key('add_after_photo_button')), findsNothing);
    expect(find.byKey(const Key('save_signature_button')), findsNothing);
    expect(find.byKey(const Key('clear_signature_button')), findsNothing);
    expect(find.byKey(const Key('work_description_field')), findsNothing);

    // …but the captured information remains visible (read-only).
    expect(find.byKey(const Key('before_photo_tile_before-1')), findsOneWidget);
    expect(find.byKey(const Key('after_photo_tile_after-1')), findsOneWidget);
    expect(find.byKey(const Key('signature_tile_sig-1')), findsOneWidget);
  });

  // 4 — the loading state prevents duplicate submissions.
  testWidgets('double-tapping submits exactly one completion', (tester) async {
    await tallSurface(tester);
    await configureCompleteable();
    await app.pump(tester);
    await openFirstJobDetails(tester);
    await tester.pump();

    // Two taps before any frame rebuilds: the cubit's in-flight guard must
    // swallow the second one.
    await tester.tap(find.byKey(const Key('complete_job_button')));
    await tester.tap(find.byKey(const Key('complete_job_button')));
    await tester.pumpAndSettle();

    expect(app.completedJobIds, <String>['job-mine']); // once
    expect(app.jobCompletedEvents, hasLength(1)); // one event
  });

  // 5 — the admin stays read-only: no completion surface at all.
  testWidgets('the admin gets no Complete Job action', (tester) async {
    await tallSurface(tester);
    await configureCompleteable(user: adminUser);
    await app.pump(tester);
    await openFirstJobDetails(tester);
    await tester.pump();

    expect(find.byKey(const Key('complete_job_button')), findsNothing);
    expect(find.text('Completion Requirements'), findsNothing);
    // Monitoring view keeps the captured data visible.
    expect(find.byKey(const Key('signature_tile_sig-1')), findsOneWidget);
    expect(app.completedJobIds, isEmpty);
  });

  // 6 — the server's refusal (another technician's job) surfaces safely.
  testWidgets('a refused completion keeps the job in progress', (tester) async {
    await tallSurface(tester);
    await configureCompleteable(
      job: _job(id: 'job-other', number: 101),
      photoDeniedJobIds: const <String>{'job-other'},
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);
    await tester.pump();

    await tester.tap(find.byKey(const Key('complete_job_button')));
    await tester.pumpAndSettle();

    expect(find.text('Unable to complete the job.'), findsOneWidget);
    expect(app.completedJobIds, isEmpty);
    expect(app.jobCompletedEvents, isEmpty);
  });

  // 7 — offline: the job is NOT falsely marked completed; the technician
  // gets the connectivity message and the job stays in progress.
  testWidgets('offline completion shows the connectivity message', (
    tester,
  ) async {
    await tallSurface(tester);
    await configureCompleteable(completionOffline: true);
    await app.pump(tester);
    await openFirstJobDetails(tester);
    await tester.pump();

    await tester.tap(find.byKey(const Key('complete_job_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Internet connection is required to complete the job.'),
      findsOneWidget,
    );
    // No fake completion happened — no local event, no status flip.
    expect(app.completedJobIds, isEmpty);
    expect(app.jobCompletedEvents, isEmpty);
    expect(find.byKey(const Key('complete_job_button')), findsOneWidget);
  });

  // 8 — an already completed job offers no workflow mutation to anyone.
  testWidgets('a completed job is read-only', (tester) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(id: 'job-mine', number: 101, status: JobStatus.completed),
      ],
      initialBeforePhotos: <String, List<JobFile>>{
        'job-mine': <JobFile>[_file('before-1', 'job-mine', 'before')],
      },
      initialAfterPhotos: <String, List<JobFile>>{
        'job-mine': <JobFile>[_file('after-1', 'job-mine', 'after')],
      },
      initialSignatures: <String, List<JobFile>>{
        'job-mine': <JobFile>[_file('sig-1', 'job-mine', 'signature')],
      },
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);
    await tester.pump();

    expect(find.byKey(const Key('complete_job_button')), findsNothing);
    expect(find.byKey(const Key('start_job_button')), findsNothing);
    expect(find.byKey(const Key('add_before_photo_button')), findsNothing);
    expect(find.byKey(const Key('add_after_photo_button')), findsNothing);
    expect(find.byKey(const Key('save_signature_button')), findsNothing);
    expect(find.byKey(const Key('work_description_field')), findsNothing);

    // Captured information remains visible.
    expect(find.byKey(const Key('signature_tile_sig-1')), findsOneWidget);
    expect(find.text('Completed Date'), findsOneWidget);
  });

  // --- Sync readiness: local existence is NOT sufficient ---------------------
  //
  // The Complete button gates on the EXISTING sync state (`syncState` +
  // failed-ids): a required file still pending/in-flight or failed keeps the
  // authoritative RPC out of reach, so the server can never be asked for a
  // completion it must reject.

  Finder completeButton() => find.byKey(const Key('complete_job_button'));

  Future<void> openReadyPageWithUnsynced(
    WidgetTester tester,
    String unsyncedType,
  ) async {
    await tallSurface(tester);
    await configureCompleteable(unsyncedType: unsyncedType);
    await app.pump(tester);
    await openFirstJobDetails(tester);
    await tester.pump();
  }

  for (final String type in <String>['before', 'after', 'signature']) {
    final String label = switch (type) {
      'before' => 'Before Photo',
      'after' => 'After Photo',
      _ => 'Customer Signature',
    };

    // 10/11/12 — a pending upload of each required kind disables Complete
    // and shows the waiting state.
    testWidgets('a pending $label keeps Complete disabled (waiting)', (
      tester,
    ) async {
      await openReadyPageWithUnsynced(tester, type);

      // The file EXISTS locally (checklist check mark)…
      final Finder section = find.byType(CompleteJobSection);
      expect(
        find.descendant(
          of: section,
          matching: find.byIcon(Icons.check_circle_rounded),
        ),
        findsNWidgets(4),
      );
      // …but its upload is not confirmed: the button stays disabled and the
      // waiting state explains why.
      final FilledButton button = tester.widget<FilledButton>(completeButton());
      expect(button.enabled, isFalse);
      expect(
        find.text('Waiting for files to finish uploading…'),
        findsOneWidget,
      );
      expect(app.completedJobIds, isEmpty);
    });
  }

  for (final String type in <String>['before', 'after', 'signature']) {
    final String label = switch (type) {
      'before' => 'Before Photo',
      'after' => 'After Photo',
      _ => 'Customer Signature',
    };

    // 13/14/15 — a FAILED upload of each required kind keeps Complete
    // disabled and reuses the existing Upload failed + Retry affordance.
    testWidgets('a failed $label keeps Complete disabled and offers Retry', (
      tester,
    ) async {
      await tallSurface(tester);
      await configureCompleteable(unsyncedType: type);
      // Mark the still-pending file as the queue's failed upload (the
      // EXISTING failed-ids plumbing the photo sections use).
      app.failedPhotoIds = <String>{
        '$type-1'.replaceFirst('signature-1', 'sig-1'),
      };
      await app.pump(tester);
      await openFirstJobDetails(tester);
      await tester.pump();

      final FilledButton button = tester.widget<FilledButton>(completeButton());
      expect(button.enabled, isFalse);
      // "Upload failed" also appears in the file's own section (existing
      // affordance) — assert the Complete section shows it too.
      final Finder section = find.byType(CompleteJobSection);
      expect(
        find.descendant(of: section, matching: find.text('Upload failed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('retry_required_files_button')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: section,
          matching: find.text('Waiting for files to finish uploading…'),
        ),
        findsNothing,
      );

      // Retry reuses the single shared retryFailedSyncs mechanism.
      await tester.tap(find.byKey(const Key('retry_required_files_button')));
      await tester.pumpAndSettle();
      expect(app.photoRetryCalls, 1);
      expect(app.completedJobIds, isEmpty);
      expect(label, isNotEmpty); // (label used in the test description)
    });
  }

  // 16 — defensive: if a completion STILL reaches the server while the local
  // file is in flight, the refusal is explained as a sync situation — never
  // a bare "missing", never a local completion.
  testWidgets('missingBeforePhoto with a local pending file explains sync', (
    tester,
  ) async {
    await tallSurface(tester);
    await configureCompleteable(unsyncedType: 'before');
    await app.pump(tester);
    await openFirstJobDetails(tester);
    await tester.pump();

    // The button is disabled — bypass it the only way left: call the cubit
    // directly (defensive path). The context must sit BELOW the page's own
    // BlocProvider — the section lives inside it.
    final JobsCubit cubit = tester
        .element(find.byType(CompleteJobSection))
        .read<JobsCubit>();
    final CompleteJobOutcome outcome = await cubit.completeJob('job-mine');
    await tester.pumpAndSettle();

    expect(outcome, CompleteJobOutcome.rejected);
    expect(cubit.state.completionError, JobCompletionError.stillSyncing);
    expect(find.text('Waiting for files to finish uploading…'), findsOneWidget);
    // Server stays authoritative: no completion happened anywhere.
    expect(app.completedJobIds, isEmpty);
    expect(app.jobCompletedEvents, isEmpty);
    expect(find.text('Missing Before Photo'), findsNothing);
  });

  // 9 — Complete Job strings exist in EN and DE.
  test('l10n: complete job strings exist in EN and DE', () {
    for (final AppLocalizations l10n in <AppLocalizations>[
      AppLocalizationsEn(),
      AppLocalizationsDe(),
    ]) {
      expect(l10n.completeJobButton, isNotEmpty);
      expect(l10n.completionRequirementsTitle, isNotEmpty);
      expect(l10n.jobCompletedMessage, isNotEmpty);
      expect(l10n.missingBeforePhotoError, isNotEmpty);
      expect(l10n.missingWorkDescriptionError, isNotEmpty);
      expect(l10n.missingAfterPhotoError, isNotEmpty);
      expect(l10n.missingSignatureError, isNotEmpty);
      expect(l10n.internetRequiredToCompleteJob, isNotEmpty);
      expect(l10n.unableToCompleteJobError, isNotEmpty);
      expect(l10n.waitingForFileSync, isNotEmpty);
    }

    const AppLocalizationsEn en = AppLocalizationsEn();
    expect(en.completeJobButton, 'Complete Job');
    expect(en.completionRequirementsTitle, 'Completion Requirements');
    expect(en.jobCompletedMessage, 'Job completed');
    expect(en.missingBeforePhotoError, 'Missing Before Photo');
    expect(en.missingWorkDescriptionError, 'Missing Work Description');
    expect(en.missingAfterPhotoError, 'Missing After Photo');
    expect(en.missingSignatureError, 'Missing Customer Signature');
    expect(
      en.internetRequiredToCompleteJob,
      'Internet connection is required to complete the job.',
    );
    expect(en.unableToCompleteJobError, 'Unable to complete the job.');
    expect(en.waitingForFileSync, 'Waiting for files to finish uploading…');

    const AppLocalizationsDe de = AppLocalizationsDe();
    expect(de.completeJobButton, isNot(en.completeJobButton));
    expect(de.jobCompletedMessage, isNot(en.jobCompletedMessage));
  });
}
