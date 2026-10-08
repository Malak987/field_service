import 'dart:io';

import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/database/tables/job_files_table.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/pages/job_details_page.dart';
import 'package:field_service/features/jobs/presentation/services/photo_picker.dart';
import 'package:field_service/features/jobs/presentation/widgets/before_photo_tile.dart';
import 'package:field_service/features/jobs/presentation/widgets/before_photos_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';
import '../../support/test_photos.dart';

/// UI tests for the Before Photos phase, against the fake jobs repository
/// (which mirrors the `register_job_file` RPC's server-side rules:
/// ownership, `in_progress` requirement, automatic capture timestamps).
///
/// End-to-end offline queue/upload/event behaviour of the REAL repository +
/// sync engine lives in `before_photos_sync_test.dart`.

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

JobFile _photo(String id, String jobId, {DateTime? capturedAt}) {
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
    tempDir = Directory.systemTemp.createTempSync('before_photos_test');
  });

  tearDown(() async {
    await app.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Tall surface: Job Details stacks header + Start + Job Info + Customer +
  /// Before Photos; on the default canvas the photo section would sit below
  /// the fold and default (onstage) finders skip offstage content.
  Future<void> tallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
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

  /// Add Before Photo → source sheet → Take Photo.
  Future<void> addPhotoViaCamera(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('add_before_photo_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('take_photo_option')));
    await tester.pumpAndSettle();
  }

  // 1 — technician adds a before photo to their own in-progress job.
  testWidgets('technician can add a before photo to their in-progress job', (
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
    expect(find.text('Before Photos'), findsOneWidget);
    expect(find.byKey(const Key('add_before_photo_button')), findsOneWidget);
    expect(find.text('No before photos yet'), findsOneWidget);

    await addPhotoViaCamera(tester);

    // The photo appears immediately as a tile; the server got exactly this
    // job; the camera was the used source (camera-first UX).
    expect(find.byType(BeforePhotoTile), findsOneWidget);
    expect(find.text('No before photos yet'), findsNothing);
    expect(app.photoAddedJobIds, <String>['job-mine']);
    expect(app.serverBeforePhotos['job-mine'], hasLength(1));
  });

  // 2 — server refuses another technician's job: nothing is registered.
  testWidgets('technician cannot add a before photo to another job', (
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
    expect(find.text('Unable to add the before photo.'), findsOneWidget);
    expect(app.photoAddedJobIds, isEmpty);
    expect(app.serverBeforePhotos['job-other'] ?? const <JobFile>[], isEmpty);
  });

  // 3 — unassigned job: the RPC's ownership chain refuses it.
  testWidgets('technician cannot add a before photo to an unassigned job', (
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

    expect(find.text('Unable to add the before photo.'), findsOneWidget);
    expect(app.photoAddedJobIds, isEmpty);
  });

  // 4 / 19 — `assigned`: no Before Photos surface, no Add action.
  testWidgets('assigned job offers no before photo capture', (tester) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(id: 'job-mine', number: 101, status: JobStatus.assigned),
      ],
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    expect(find.byType(BeforePhotosSection), findsNothing);
    expect(find.text('Before Photos'), findsNothing);
    expect(find.byKey(const Key('add_before_photo_button')), findsNothing);
  });

  // 5 / 19 — completed: existing photos stay visible, capture is gone.
  testWidgets('completed job shows photos read-only (no Add)', (tester) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(id: 'job-mine', number: 101, status: JobStatus.completed),
      ],
      initialBeforePhotos: <String, List<JobFile>>{
        'job-mine': <JobFile>[_photo('p1', 'job-mine')],
      },
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    expect(find.text('Before Photos'), findsOneWidget);
    expect(find.byType(BeforePhotoTile), findsOneWidget);
    expect(find.byKey(const Key('add_before_photo_button')), findsNothing);
  });

  // 5b — cancelled: same rule.
  testWidgets('cancelled job offers no before photo capture', (tester) async {
    await tallSurface(tester);
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(id: 'job-mine', number: 101, status: JobStatus.cancelled),
      ],
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    expect(find.byKey(const Key('add_before_photo_button')), findsNothing);
  });

  // 6 — admin can view a job's before photos (existing Jobs architecture).
  testWidgets('admin can view before photos of a job', (tester) async {
    await tallSurface(tester);
    await app.configure(
      user: adminUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
      initialBeforePhotos: <String, List<JobFile>>{
        'job-mine': <JobFile>[
          _photo('p1', 'job-mine'),
          _photo('p2', 'job-mine'),
        ],
      },
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    expect(find.text('Before Photos'), findsOneWidget);
    expect(find.byType(BeforePhotoTile), findsNWidgets(2));
  });

  // 7 — multiple before photos on one job (never limited to one).
  testWidgets('multiple before photos can be added to one job', (tester) async {
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

    expect(find.byType(BeforePhotoTile), findsNWidgets(3));
    expect(app.serverBeforePhotos['job-mine'], hasLength(3));
  });

  // 8 — the capture timestamp is recorded automatically (never manual).
  testWidgets('capture timestamp is stored automatically', (tester) async {
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

    expect(app.photoCapturedAt, hasLength(1));
    final DateTime capturedAt = app.photoCapturedAt.single;
    expect(
      capturedAt.isBefore(before.subtract(const Duration(minutes: 1))),
      isFalse,
    );
    expect(capturedAt.isAfter(after.add(const Duration(minutes: 1))), isFalse);
    // The registered file carries the same automatic timestamp.
    expect(app.serverBeforePhotos['job-mine']!.single.capturedAt, capturedAt);
  });

  // 9 — gallery remains available as the second, explicit choice.
  testWidgets('gallery selection is offered as a fallback source', (
    tester,
  ) async {
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

    await tester.tap(find.byKey(const Key('add_before_photo_button')));
    await tester.pumpAndSettle();
    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Choose from Gallery'), findsOneWidget);

    await tester.tap(find.byKey(const Key('choose_from_gallery_option')));
    await tester.pumpAndSettle();

    expect(picker.lastSource, PhotoPickSource.gallery);
    expect(find.byType(BeforePhotoTile), findsOneWidget);
  });

  // 10 — camera failure maps to a localized, safe message.
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
    expect(app.photoAddedJobIds, isEmpty);
    expect(find.byType(BeforePhotoTile), findsNothing);
  });

  // 11 — cancelled pick is silent and registers nothing.
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

    expect(app.photoAddedJobIds, isEmpty);
    expect(find.byType(BeforePhotoTile), findsNothing);
    expect(find.text('Unable to add the before photo.'), findsNothing);
  });

  // 12 — failed uploads surface with Retry; retry uses the shared engine.
  testWidgets('failed upload shows Upload failed + Retry, retry re-queues', (
    tester,
  ) async {
    await tallSurface(tester);
    final JobFile failing = _photo('p-fail', 'job-mine');
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
      initialBeforePhotos: <String, List<JobFile>>{
        'job-mine': <JobFile>[failing],
      },
    );
    app.failedPhotoIds = <String>{'p-fail'};
    await app.pump(tester);
    await openFirstJobDetails(tester);

    expect(find.text('Upload failed'), findsOneWidget);
    expect(find.byKey(const Key('retry_before_photos_button')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.byKey(const Key('retry_before_photos_button')));
    await tester.pumpAndSettle();

    expect(app.photoRetryCalls, 1);
    // The fake retry succeeds: the failed badge row disappears.
    expect(find.byKey(const Key('retry_before_photos_button')), findsNothing);
  });

  // 13 — sync-state badges: pending shows the upload icon, synced the check.
  testWidgets('photo tiles carry their sync-state badge', (tester) async {
    await tallSurface(tester);
    final JobFile synced = _photo('p-synced', 'job-mine');
    final JobFile pending = JobFile(
      id: 'p-pending',
      jobId: 'job-mine',
      fileType: JobFileType.before.name,
      fileName: 'pending.jpg',
      capturedAt: DateTime.utc(2026, 9, 2, 11),
      localPath: 'before/p-pending.jpg',
      syncState: JobFileSyncState.pending,
    );
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-mine', number: 101)],
      initialBeforePhotos: <String, List<JobFile>>{
        'job-mine': <JobFile>[synced, pending],
      },
    );
    await app.pump(tester);
    await openFirstJobDetails(tester);

    expect(find.byType(BeforePhotoTile), findsNWidgets(2));
    expect(find.byTooltip('Pending sync'), findsOneWidget);
    expect(find.byTooltip('Synced'), findsOneWidget);
  });
}
