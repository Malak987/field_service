import 'dart:io';

import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/database/tables/job_files_table.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/pages/job_details_page.dart';
import 'package:field_service/features/jobs/presentation/services/photo_picker.dart';
import 'package:field_service/features/jobs/presentation/widgets/after_photos_section.dart';
import 'package:field_service/features/jobs/presentation/widgets/before_photo_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';
import '../../support/test_photos.dart';

/// UI tests for the After Photos phase, against the fake jobs repository
/// (which mirrors the `register_job_file` RPC's server-side rules:
/// ownership, `in_progress` requirement, automatic capture timestamps).
///
/// End-to-end offline queue/upload/event behaviour of the REAL repository +
/// sync engine lives in `after_photos_sync_test.dart`.

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

JobFile _afterPhoto(String id, String jobId, {DateTime? capturedAt}) {
  return JobFile(
    id: id,
    jobId: jobId,
    fileType: JobFileType.after.name,
    fileName: '$id.jpg',
    mimeType: 'image/jpeg',
    capturedAt: capturedAt ?? DateTime.utc(2026, 9, 2, 16),
    remotePath: 'jobs/$jobId/after/$id.jpg',
    syncState: JobFileSyncState.synced,
  );
}

JobFile _beforePhoto(String id, String jobId, {DateTime? capturedAt}) {
  return JobFile(
    id: id,
    jobId: jobId,
    fileType: JobFileType.before.name,
    fileName: '$id.jpg',
    mimeType: 'image/jpeg',
    capturedAt: capturedAt ?? DateTime.utc(2026, 9, 2, 10),
    remotePath: 'jobs/$jobId/before/$id.jpg',
    syncState: JobFileSyncState.synced,
  );
}

/// Fake camera/gallery: serves prepared file paths, one per pick.
class _FakePhotoPicker implements PhotoPicker {
  _FakePhotoPicker(this.paths, {this.error});

  final List<String> paths;
  final PhotoPickException? error;
  int _index = 0;

  /// The source of the last pick (camera-first assertions).
  PhotoPickSource? lastSource;

  @override
  Future<PickedPhoto?> pick({required PhotoPickSource source}) async {
    lastSource = source;
    final PhotoPickException? failure = error;
    if (failure != null) {
      throw failure;
    }
    if (_index >= paths.length) {
      return null; // Simulates the user cancelling.
    }
    return PickedPhoto(path: paths[_index++], mimeType: 'image/jpeg');
  }
}

void main() {
  late AppTestHarness app;
  late Directory tempDir;

  setUp(() {
    app = AppTestHarness();
    // Sync I/O: widget-test bodies run under FakeAsync where awaiting
    // dart:io futures never completes.
    tempDir = Directory.systemTemp.createTempSync('after_photos_test');
  });

  tearDown(() async {
    await app.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Tall surface: Job Details stacks header + Start + Job Info + Customer +
  /// Before Photos + Work Description + After Photos — the after section sits
  /// lowest, so the canvas must be tall and the add button scrolled into view.
  Future<void> tallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<void> registerPicker(_FakePhotoPicker picker) async {
    await sl.unregister<PhotoPicker>();
    sl.registerSingleton<PhotoPicker>(picker);
  }

  /// Dashboard → Jobs → first job card → details.
  Future<void> openFirstJobDetails(WidgetTester tester) async {
    await tester.tap(find.text('View Jobs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#101'));
    await tester.pumpAndSettle();
    expect(find.byType(JobDetailsPage), findsOneWidget);
  }

  /// Add After Photo → source sheet → Take Photo.
  Future<void> addPhotoViaCamera(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('add_after_photo_button')));
    await tester.tap(find.byKey(const Key('add_after_photo_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('take_photo_option')));
    await tester.pumpAndSettle();
  }

  Finder afterTiles() => find.descendant(
    of: find.byKey(const Key('after_photos_grid')),
    matching: find.byType(BeforePhotoTile),
  );

  Finder beforeTiles() => find.descendant(
    of: find.byKey(const Key('before_photos_grid')),
    matching: find.byType(BeforePhotoTile),
  );

  // 1 — technician adds an after photo to their own in-progress job.
  testWidgets('technician can add an after photo to their in-progress job', (
    tester,
  ) async {
    await tallSurface(tester);
    final File photo = writeTempPhoto(tempDir, 'shot1.jpg');
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
    );
    await registerPicker(_FakePhotoPicker(<String>[photo.path]));
    await app.pump(tester);
    await openFirstJobDetails(tester);

    // Section for a started job: title + add action, empty state first.
    // (Scoped to the section title: the Complete Job checklist below repeats
    // the same label as one of its requirement rows.)
    expect(
      find.descendant(
        of: find.byType(AfterPhotosSection),
        matching: find.text('After Photos'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('add_after_photo_button')), findsOneWidget);
    expect(find.text('No after photos yet'), findsOneWidget);

    await addPhotoViaCamera(tester);

    // The photo appears immediately as a tile in the AFTER grid; the server
    // got exactly this job; the camera was the used source (camera-first UX).
    expect(afterTiles(), findsOneWidget);
    expect(find.text('No after photos yet'), findsNothing);
    expect(app.afterPhotoAddedJobIds, <String>['job-mine']);
    expect(app.serverAfterPhotos['job-mine'], hasLength(1));
    // The Before Photos section is untouched.
    expect(app.serverBeforePhotos['job-mine'] ?? const <JobFile>[], isEmpty);
  });

  // 2 — server refuses another technician's job: nothing is registered.
  testWidgets('technician cannot add an after photo to another job', (
    tester,
  ) async {
    await tallSurface(tester);
    final File photo = writeTempPhoto(tempDir, 'shot1.jpg');
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-other', number: 101)],
      photoDeniedJobIds: const <String>{'job-other'},
    );
    await registerPicker(_FakePhotoPicker(<String>[photo.path]));
    await app.pump(tester);
    await openFirstJobDetails(tester);

    await addPhotoViaCamera(tester);

    // The server-side refusal surfaces as a safe message; nothing stored.
    expect(find.text('Unable to add the after photo.'), findsOneWidget);
    expect(app.afterPhotoAddedJobIds, isEmpty);
    expect(app.serverAfterPhotos['job-other'] ?? const <JobFile>[], isEmpty);
  });

  // 3 — unassigned job: the RPC's ownership chain refuses it.
  testWidgets('technician cannot add an after photo to an unassigned job', (
    tester,
  ) async {
    await tallSurface(tester);
    final File photo = writeTempPhoto(tempDir, 'shot1.jpg');
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(id: 'job-unassigned', number: 101, assignedEmployeeId: null),
      ],
    );
    await registerPicker(_FakePhotoPicker(<String>[photo.path]));
    await app.pump(tester);
    await openFirstJobDetails(tester);

    await addPhotoViaCamera(tester);

    expect(find.text('Unable to add the after photo.'), findsOneWidget);
    expect(app.afterPhotoAddedJobIds, isEmpty);
  });

  // 4 — `assigned`: no After Photos surface, no Add action.
  testWidgets('assigned job offers no after photo capture', (tester) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(id: 'job-mine', number: 101, status: JobStatus.assigned),
      ],
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    expect(find.byType(AfterPhotosSection), findsNothing);
    expect(find.text('After Photos'), findsNothing);
    expect(find.byKey(const Key('add_after_photo_button')), findsNothing);
  });

  // 5 — completed: existing after photos stay visible, capture is gone.
  testWidgets('completed job shows after photos read-only (no Add)', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(id: 'job-mine', number: 101, status: JobStatus.completed),
      ],
      initialAfterPhotos: <String, List<JobFile>>{
        'job-mine': <JobFile>[_afterPhoto('a1', 'job-mine')],
      },
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    expect(find.text('After Photos'), findsOneWidget);
    expect(afterTiles(), findsOneWidget);
    expect(find.byKey(const Key('add_after_photo_button')), findsNothing);
  });

  // 6 — cancelled: same rule.
  testWidgets('cancelled job offers no after photo capture', (tester) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(id: 'job-mine', number: 101, status: JobStatus.cancelled),
      ],
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    expect(find.byKey(const Key('add_after_photo_button')), findsNothing);
  });

  // 7 — admin can VIEW after photos (monitoring) but never gets the Add
  // action — capturing is a technician execution action.
  testWidgets('admin sees after photos read-only (no Add)', (tester) async {
    await tallSurface(tester);
    await app.configure(
      user: adminUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
      initialAfterPhotos: <String, List<JobFile>>{
        'job-mine': <JobFile>[
          _afterPhoto('a1', 'job-mine'),
          _afterPhoto('a2', 'job-mine'),
        ],
      },
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    expect(find.text('After Photos'), findsOneWidget);
    expect(afterTiles(), findsNWidgets(2));
    expect(find.byKey(const Key('add_after_photo_button')), findsNothing);
  });

  // 8 — multiple after photos on one job (never limited to one).
  testWidgets('multiple after photos can be added to one job', (tester) async {
    await tallSurface(tester);
    final List<File> shots = <File>[
      writeTempPhoto(tempDir, 'shot1.jpg'),
      writeTempPhoto(tempDir, 'shot2.jpg'),
      writeTempPhoto(tempDir, 'shot3.jpg'),
    ];
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
    );
    await registerPicker(
      _FakePhotoPicker(<String>[for (final File f in shots) f.path]),
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    for (int i = 0; i < 3; i++) {
      await addPhotoViaCamera(tester);
    }

    expect(afterTiles(), findsNWidgets(3));
    expect(app.serverAfterPhotos['job-mine'], hasLength(3));
  });

  // 9 — the capture timestamp is recorded automatically (never manual).
  testWidgets('after capture timestamp is stored automatically', (
    tester,
  ) async {
    await tallSurface(tester);
    final File photo = writeTempPhoto(tempDir, 'shot1.jpg');
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
    );
    await registerPicker(_FakePhotoPicker(<String>[photo.path]));
    await app.pump(tester);
    await openFirstJobDetails(tester);

    final DateTime before = DateTime.now();
    await addPhotoViaCamera(tester);
    final DateTime after = DateTime.now();

    expect(app.afterPhotoCapturedAt, hasLength(1));
    final DateTime capturedAt = app.afterPhotoCapturedAt.single;
    expect(
      capturedAt.isBefore(before.subtract(const Duration(minutes: 1))),
      isFalse,
    );
    expect(capturedAt.isAfter(after.add(const Duration(minutes: 1))), isFalse);
    // The registered file carries the same automatic timestamp.
    expect(app.serverAfterPhotos['job-mine']!.single.capturedAt, capturedAt);
  });

  // 10 — gallery remains available as the second, explicit choice.
  testWidgets('gallery selection is offered for after photos', (tester) async {
    await tallSurface(tester);
    final File photo = writeTempPhoto(tempDir, 'gallery1.jpg');
    final _FakePhotoPicker picker = _FakePhotoPicker(<String>[photo.path]);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
    );
    await registerPicker(picker);
    await app.pump(tester);
    await openFirstJobDetails(tester);

    await tester.ensureVisible(find.byKey(const Key('add_after_photo_button')));
    await tester.tap(find.byKey(const Key('add_after_photo_button')));
    await tester.pumpAndSettle();
    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Choose from Gallery'), findsOneWidget);

    await tester.tap(find.byKey(const Key('choose_from_gallery_option')));
    await tester.pumpAndSettle();

    expect(picker.lastSource, PhotoPickSource.gallery);
    expect(afterTiles(), findsOneWidget);
  });

  // 11 — camera failure maps to a localized, safe message.
  testWidgets('camera unavailability is reported, nothing registered', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
    );
    await registerPicker(
      _FakePhotoPicker(
        const <String>[],
        error: const PhotoPickException(PhotoPickFailure.cameraUnavailable),
      ),
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    await addPhotoViaCamera(tester);

    expect(
      find.text('The camera is not available on this device.'),
      findsOneWidget,
    );
    expect(app.afterPhotoAddedJobIds, isEmpty);
    expect(afterTiles(), findsNothing);
  });

  // 12 — cancelled pick is silent and registers nothing.
  testWidgets('cancelling the camera registers nothing and shows no error', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
    );
    await registerPicker(_FakePhotoPicker(const <String>[])); // cancels
    await app.pump(tester);
    await openFirstJobDetails(tester);

    await addPhotoViaCamera(tester);

    expect(app.afterPhotoAddedJobIds, isEmpty);
    expect(afterTiles(), findsNothing);
    expect(find.text('Unable to add the after photo.'), findsNothing);
  });

  // 13 — failed uploads surface with Retry; retry uses the shared engine.
  testWidgets('failed after upload shows Upload failed + Retry', (
    tester,
  ) async {
    await tallSurface(tester);
    final JobFile failing = _afterPhoto('a-fail', 'job-mine');
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
      initialAfterPhotos: <String, List<JobFile>>{
        'job-mine': <JobFile>[failing],
      },
    );
    app.failedPhotoIds = <String>{'a-fail'};
    await app.pump(tester);
    await openFirstJobDetails(tester);

    // Exactly ONE failure row in the whole page — the after section's.
    expect(find.text('Upload failed'), findsOneWidget);
    expect(find.byKey(const Key('retry_after_photos_button')), findsOneWidget);
    expect(find.byKey(const Key('retry_before_photos_button')), findsNothing);

    await tester.ensureVisible(
      find.byKey(const Key('retry_after_photos_button')),
    );
    await tester.tap(find.byKey(const Key('retry_after_photos_button')));
    await tester.pumpAndSettle();

    expect(app.photoRetryCalls, 1);
    // The fake retry succeeds: the failed badge row disappears.
    expect(find.byKey(const Key('retry_after_photos_button')), findsNothing);
  });

  // 14 — sync-state badges: pending shows the upload icon, synced the check.
  testWidgets('after photo tiles carry their sync-state badge', (tester) async {
    await tallSurface(tester);
    final JobFile synced = _afterPhoto('a-synced', 'job-mine');
    final JobFile pending = JobFile(
      id: 'a-pending',
      jobId: 'job-mine',
      fileType: JobFileType.after.name,
      fileName: 'pending.jpg',
      capturedAt: DateTime.utc(2026, 9, 2, 17),
      localPath: 'after/a-pending.jpg',
      syncState: JobFileSyncState.pending,
    );
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
      initialAfterPhotos: <String, List<JobFile>>{
        'job-mine': <JobFile>[synced, pending],
      },
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    expect(afterTiles(), findsNWidgets(2));
    expect(find.byTooltip('Pending sync'), findsOneWidget);
    expect(find.byTooltip('Synced'), findsOneWidget);
  });

  // 15 — separation: before photos never appear in the After section and
  // vice versa (the grids are fed by file-type-filtered watches).
  testWidgets('before and after photos stay in their own sections', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
      initialBeforePhotos: <String, List<JobFile>>{
        'job-mine': <JobFile>[
          _beforePhoto('b1', 'job-mine'),
          _beforePhoto('b2', 'job-mine'),
        ],
      },
      initialAfterPhotos: <String, List<JobFile>>{
        'job-mine': <JobFile>[_afterPhoto('a1', 'job-mine')],
      },
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    expect(beforeTiles(), findsNWidgets(2));
    expect(afterTiles(), findsOneWidget);
    // The two grids hold disjoint file ids.
    expect(find.byKey(const Key('before_photo_tile_b1')), findsOneWidget);
    expect(find.byKey(const Key('before_photo_tile_b2')), findsOneWidget);
    expect(find.byKey(const Key('after_photo_tile_a1')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('after_photos_grid')),
        matching: find.byKey(const Key('before_photo_tile_b1')),
      ),
      findsNothing,
    );
  });
}
