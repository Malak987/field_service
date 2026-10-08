import 'dart:io';

import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/pages/job_details_page.dart';
import 'package:field_service/features/jobs/presentation/widgets/after_photos_section.dart';
import 'package:field_service/features/jobs/presentation/widgets/signature_pad.dart';
import 'package:field_service/features/jobs/presentation/widgets/signature_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';

/// UI tests for the Customer Signature section, against the fake jobs
/// repository (which mirrors the `register_job_file` RPC's server-side
/// rules: ownership, `in_progress` requirement, automatic capture
/// timestamps). Real offline/sync behaviour lives in
/// `signature_sync_test.dart`; the RPC contract lives in
/// `signature_wire_test.dart`.

Job _job({
  required String id,
  required int number,
  String? assignedEmployeeId = 'emp-tech-1',
  String status = JobStatus.inProgress,
}) {
  return Job(
    id: id,
    jobNumber: number,
    customerId: 'cust-$id',
    assignedEmployeeId: assignedEmployeeId,
    jobType: 'kitchen_renovation',
    description: 'Fix the sink.',
    status: JobStatus(status),
    startedAt: status == JobStatus.assigned ? null : DateTime.utc(2026, 9, 2),
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
    expiresAt: DateTime.utc(2026, 12, 1),
  );
}

JobFile _signature(String id, String jobId, {DateTime? capturedAt}) {
  return JobFile(
    id: id,
    jobId: jobId,
    fileType: 'signature',
    fileName: 'signature.png',
    mimeType: 'image/png',
    capturedAt: capturedAt ?? DateTime.utc(2026, 9, 2, 16, 45),
    remotePath: 'jobs/$jobId/signature/$id.png',
    syncState: JobFileSyncState.synced,
  );
}

void main() {
  late AppTestHarness app;

  setUp(() => app = AppTestHarness());
  tearDown(() => app.dispose());

  /// Job Details stacks many cards; the signature section sits lowest.
  Future<void> tallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
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

  /// Draws a stroke inside the signature pad.
  Future<void> drawSignature(WidgetTester tester) async {
    final Offset center = tester.getCenter(find.byType(SignaturePad));
    final TestGesture gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(60, 24));
    await gesture.moveBy(const Offset(60, -32));
    await gesture.moveBy(const Offset(48, 16));
    await gesture.up();
    await tester.pump();
  }

  /// Taps **Save Signature**. The tap runs inside [WidgetTester.runAsync]
  /// because confirming a non-empty drawing calls
  /// `RepaintBoundary.toImage`, which needs REAL async time: the fire-and-
  /// forget tap handler must be given real frames until the export and the
  /// cubit round-trip complete (FakeAsync pumping alone would never resolve
  /// the image future).
  Future<void> tapSave(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('save_signature_button')));
      for (int i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
  }

  // 1 — technician captures a signature on their own in-progress job.
  testWidgets('technician can capture a signature on an in-progress job', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    // Section surface: title, drawing pad with hint, Clear + Save.
    // (Scoped to the section title: the Complete Job checklist below repeats
    // the same label as one of its requirement rows.)
    expect(
      find.descendant(
        of: find.byType(SignatureSection),
        matching: find.text('Customer Signature'),
      ),
      findsOneWidget,
    );
    expect(find.byType(SignaturePad), findsOneWidget);
    expect(find.text('Customer signs here'), findsOneWidget);
    expect(find.byKey(const Key('clear_signature_button')), findsOneWidget);
    expect(find.byKey(const Key('save_signature_button')), findsOneWidget);
    expect(find.text('No signature yet'), findsNothing);

    await drawSignature(tester);
    // Hint disappears once ink exists.
    expect(find.text('Customer signs here'), findsNothing);

    await tapSave(tester);

    // Success snackbar + the fake server registered exactly this capture.
    expect(find.text('Signature saved'), findsOneWidget);
    expect(app.signatureCapturedJobIds, <String>['job-mine']);
    expect(app.signatureImages['job-mine'], hasLength(1));
    expect(app.signatureImages['job-mine']!.single, isNotEmpty);
    // The automatic capture timestamp was recorded by the "server".
    expect(app.signatureCapturedAt, hasLength(1));

    // The preview replaces the pad immediately (local-first).
    expect(find.byType(SignaturePad), findsNothing);
    expect(
      find.byKey(
        Key('signature_tile_${app.serverSignatures['job-mine']!.single.id}'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('save_signature_button')), findsNothing);
    expect(find.byKey(const Key('clear_signature_button')), findsNothing);
  });

  // 2 — an EMPTY drawing is rejected inline; nothing is stored or queued.
  testWidgets('an empty signature is rejected with an inline error', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    await tester.ensureVisible(find.byKey(const Key('save_signature_button')));
    await tester.tap(find.byKey(const Key('save_signature_button')));
    await tester.pumpAndSettle();

    expect(find.text('Signature required'), findsOneWidget);
    expect(find.text('Signature saved'), findsNothing);
    expect(app.signatureCapturedJobIds, isEmpty);
    expect(app.signatureImages, isEmpty);
    // The pad stays for a redraw.
    expect(find.byType(SignaturePad), findsOneWidget);
  });

  // 3 — Clear empties the pad, so the next save attempt is rejected again.
  testWidgets('Clear empties the drawing before saving', (tester) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    await drawSignature(tester);
    expect(find.text('Customer signs here'), findsNothing);

    await tester.tap(find.byKey(const Key('clear_signature_button')));
    await tester.pump();
    // Cleared: the placeholder hint returns, save refuses again.
    expect(find.text('Customer signs here'), findsOneWidget);

    await tapSave(tester);

    expect(find.text('Signature required'), findsOneWidget);
    expect(app.signatureCapturedJobIds, isEmpty);
  });

  // 4 — another technician's job: server-side refusal, failure snackbar.
  testWidgets('a signature for another technician\'s job is refused', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-other', number: 101)],
      photoDeniedJobIds: const <String>{'job-other'},
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    await drawSignature(tester);
    await tapSave(tester);

    expect(find.text('Failed to save signature'), findsOneWidget);
    expect(app.signatureCapturedJobIds, isEmpty);
    expect(app.serverSignatures['job-other'] ?? const <JobFile>[], isEmpty);
  });

  // 5 — an unassigned job is refused by the same ownership rule.
  testWidgets('a signature for an unassigned job is refused', (tester) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(id: 'job-unassigned', number: 101, assignedEmployeeId: null),
      ],
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    await drawSignature(tester);
    await tapSave(tester);

    expect(find.text('Failed to save signature'), findsOneWidget);
    expect(app.signatureCapturedJobIds, isEmpty);
  });

  // 6 — job not `in_progress` (completed): read-only section, no capture.
  testWidgets('a completed job shows no signature capture controls', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(id: 'job-done', number: 101, status: JobStatus.completed),
      ],
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    expect(find.text('Customer Signature'), findsOneWidget);
    expect(find.text('No signature yet'), findsOneWidget);
    expect(find.byType(SignaturePad), findsNothing);
    expect(find.byKey(const Key('save_signature_button')), findsNothing);
    expect(find.byKey(const Key('clear_signature_button')), findsNothing);
  });

  // 7 — a captured signature on a completed job: preview only, no pad.
  testWidgets('a captured signature stays read-only on a completed job', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(id: 'job-done', number: 101, status: JobStatus.completed),
      ],
      initialSignatures: <String, List<JobFile>>{
        'job-done': <JobFile>[_signature('sig-1', 'job-done')],
      },
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);
    await tester.pump();

    expect(find.byKey(const Key('signature_tile_sig-1')), findsOneWidget);
    expect(find.byType(SignaturePad), findsNothing);
    expect(find.byKey(const Key('save_signature_button')), findsNothing);
    expect(find.byKey(const Key('clear_signature_button')), findsNothing);
  });

  // 8 — admin: monitoring view only — never any capture control.
  testWidgets('the admin only sees the signature read-only', (tester) async {
    await tallSurface(tester);
    await app.configure(
      user: adminUser,
      jobs: <Job>[_job(id: 'job-tech', number: 101)],
      initialSignatures: <String, List<JobFile>>{
        'job-tech': <JobFile>[_signature('sig-1', 'job-tech')],
      },
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);
    await tester.pump();

    expect(find.byKey(const Key('signature_tile_sig-1')), findsOneWidget);
    expect(find.byType(SignaturePad), findsNothing);
    expect(find.byKey(const Key('save_signature_button')), findsNothing);
    expect(find.byKey(const Key('clear_signature_button')), findsNothing);
    expect(app.signatureCapturedJobIds, isEmpty);
  });

  // 9 — admin on a job without a signature: the read-only empty note.
  testWidgets('the admin sees the empty read-only state', (tester) async {
    await tallSurface(tester);
    await app.configure(
      user: adminUser,
      jobs: <Job>[_job(id: 'job-tech', number: 101)],
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    expect(find.text('Customer Signature'), findsOneWidget);
    expect(find.text('No signature yet'), findsOneWidget);
    expect(find.byType(SignaturePad), findsNothing);
    expect(find.byKey(const Key('save_signature_button')), findsNothing);
  });

  // 10 — `assigned` (not started): no signature section at all.
  testWidgets('an assigned job offers no signature section', (tester) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(id: 'job-mine', number: 101, status: JobStatus.assigned),
      ],
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    expect(find.text('Customer Signature'), findsNothing);
    expect(find.byType(SignaturePad), findsNothing);
  });

  // 11 — placement: the signature card sits directly below After Photos,
  // and signature files never leak into the photo grids (or vice versa).
  testWidgets('the section sits after After Photos and stays separate', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
      initialBeforePhotos: <String, List<JobFile>>{
        'job-mine': <JobFile>[
          JobFile(
            id: 'before-1',
            jobId: 'job-mine',
            fileType: 'before',
            fileName: 'before-1.jpg',
            mimeType: 'image/jpeg',
            capturedAt: DateTime.utc(2026, 9, 2, 10),
            remotePath: 'jobs/job-mine/before/before-1.jpg',
            syncState: JobFileSyncState.synced,
          ),
        ],
      },
      initialAfterPhotos: <String, List<JobFile>>{
        'job-mine': <JobFile>[
          JobFile(
            id: 'after-1',
            jobId: 'job-mine',
            fileType: 'after',
            fileName: 'after-1.jpg',
            mimeType: 'image/jpeg',
            capturedAt: DateTime.utc(2026, 9, 2, 16),
            remotePath: 'jobs/job-mine/after/after-1.jpg',
            syncState: JobFileSyncState.synced,
          ),
        ],
      },
      initialSignatures: <String, List<JobFile>>{
        'job-mine': <JobFile>[_signature('sig-1', 'job-mine')],
      },
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);
    await tester.pump();

    // Each file type renders ONLY in its own section.
    expect(find.byKey(const Key('signature_tile_sig-1')), findsOneWidget);
    expect(find.byKey(const Key('before_photo_tile_before-1')), findsOneWidget);
    expect(find.byKey(const Key('after_photo_tile_after-1')), findsOneWidget);

    // Layout order: After Photos title above the Customer Signature title.
    // (Both titles also appear as Complete Job checklist rows — scope to the
    // section titles.)
    final Finder afterTitle = find.descendant(
      of: find.byType(AfterPhotosSection),
      matching: find.text('After Photos'),
    );
    final Finder signatureTitle = find.descendant(
      of: find.byType(SignatureSection),
      matching: find.text('Customer Signature'),
    );
    expect(afterTitle, findsOneWidget);
    expect(signatureTitle, findsOneWidget);
    final double afterDy = tester.getTopLeft(afterTitle).dy;
    final double signatureDy = tester.getTopLeft(signatureTitle).dy;
    expect(signatureDy, greaterThan(afterDy));
  });

  // 12 — all Customer Signature strings exist in EN and DE.
  test('l10n: signature strings exist in EN and DE', () {
    for (final AppLocalizations l10n in <AppLocalizations>[
      AppLocalizationsEn(),
      AppLocalizationsDe(),
    ]) {
      expect(l10n.customerSignatureTitle, isNotEmpty);
      expect(l10n.signatureHint, isNotEmpty);
      expect(l10n.clearButton, isNotEmpty);
      expect(l10n.saveSignatureButton, isNotEmpty);
      expect(l10n.signatureRequiredError, isNotEmpty);
      expect(l10n.signatureSavedMessage, isNotEmpty);
      expect(l10n.signatureSaveFailedMessage, isNotEmpty);
      expect(l10n.noSignatureYet, isNotEmpty);
    }

    // EN values match the product copy.
    const AppLocalizationsEn en = AppLocalizationsEn();
    expect(en.customerSignatureTitle, 'Customer Signature');
    expect(en.clearButton, 'Clear');
    expect(en.saveSignatureButton, 'Save Signature');
    expect(en.signatureRequiredError, 'Signature required');
    expect(en.signatureSavedMessage, 'Signature saved');
    expect(en.signatureSaveFailedMessage, 'Failed to save signature');
    expect(en.noSignatureYet, 'No signature yet');

    // DE is structurally complete and genuinely localized.
    const AppLocalizationsDe de = AppLocalizationsDe();
    expect(de.customerSignatureTitle, isNot(en.customerSignatureTitle));
    expect(de.saveSignatureButton, isNot(en.saveSignatureButton));
  });

  // 13 — the signature widgets stay presentational: no data-layer imports.
  test('signature widgets contain no storage/network/DB access', () {
    // Sync I/O: bare test() outside FakeAsync.
    for (final String path in <String>[
      'lib/features/jobs/presentation/widgets/signature_section.dart',
      'lib/features/jobs/presentation/widgets/signature_pad.dart',
    ]) {
      final String source = File(path).readAsStringSync();
      expect(source.contains('supabase'), isFalse, reason: path);
      expect(source.contains('drift'), isFalse, reason: path);
      expect(source.contains('/repositories/'), isFalse, reason: path);
      expect(source.contains('/datasources/'), isFalse, reason: path);
      expect(source.contains('core/storage/'), isFalse, reason: path);
      expect(source.contains('core/sync/'), isFalse, reason: path);
    }
  });

  // 14 — the core signature-UX guarantee: while a finger draws inside the
  // pad, the job details page must NOT scroll. Every touch on the pad
  // becomes ink; the page only scrolls again once the finger lifts.
  testWidgets('drawing on the signature pad never scrolls the page', (
    tester,
  ) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-1', number: 101)],
    );
    await app.pump(tester);
    // A viewport smaller than the page: scrolling is possible at all, so
    // this test can actually catch a scroll-during-draw regression.
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openFirstJobDetails(tester);

    // The lazy ListView only builds the pad once it is scrolled into view.
    await tester.dragUntilVisible(
      find.byType(SignaturePad),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    final Element padElement = tester.element(find.byType(SignaturePad));
    final ScrollPosition position = Scrollable.of(padElement).position;
    final double offsetBefore = position.pixels;
    expect(offsetBefore, greaterThan(0)); // scrolled down to the pad

    // A long vertical finger movement — exactly the motion that used to
    // scroll the page instead of drawing. Pumps interleave with the moves
    // the way real frames arrive on a device.
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(SignaturePad)),
    );
    for (int i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    // The finger produced a visible signature…
    final SignaturePadState pad = tester.state<SignaturePadState>(
      find.byType(SignaturePad),
    );
    expect(pad.isEmpty, isFalse);
    // …and the page did not move a single pixel.
    expect(position.pixels, offsetBefore);
  });

  // 15 — the other half of the guarantee: outside the pad the page keeps
  // its normal scrolling behaviour.
  testWidgets('the page still scrolls when touching outside the pad', (
    tester,
  ) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-1', number: 101)],
    );
    await app.pump(tester);
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openFirstJobDetails(tester);
    await tester.pumpAndSettle();

    final Element headerElement = tester.element(find.text('#101').first);
    final ScrollPosition position = Scrollable.of(headerElement).position;
    expect(position.pixels, 0);

    // Drag from the top of the page (header area — far above the pad).
    final TestGesture gesture = await tester.startGesture(
      const Offset(500, 300),
    );
    for (int i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(0));
  });
}
