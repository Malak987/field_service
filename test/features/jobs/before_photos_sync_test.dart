import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/database/app_database.dart';
import 'package:field_service/core/network/network_info.dart';
import 'package:field_service/core/storage/app_file_storage.dart';
import 'package:field_service/core/storage/file_storage.dart';
import 'package:field_service/core/storage/local_file_storage.dart';
import 'package:field_service/core/sync/sync_handler.dart';
import 'package:field_service/core/sync/sync_manager.dart';
import 'package:field_service/core/sync/sync_operation.dart';
import 'package:field_service/core/sync/sync_processor.dart';
import 'package:field_service/core/sync/sync_queue.dart';
import 'package:field_service/features/jobs/data/datasources/job_files_remote_data_source.dart';
import 'package:field_service/features/jobs/data/datasources/jobs_remote_data_source.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';
import '../../support/test_photos.dart';

/// Offline/sync tests for Before Photos against the REAL stack:
/// `JobsRepositoryImpl` + `LocalFileStorage` + app-owned `FileStorage`
/// (temp directory) + durable Drift `SyncQueue` + shared `SyncManager`
/// + `JobFileSyncHandler`. Only the remote surfaces (Storage + the
/// `register_job_file` RPC + the `job_files` table) are faked — with the
/// SAME semantics as `supabase/before_photos_setup.sql`.

/// Fake of Supabase Storage + `job_files` + `register_job_file` with the
/// server's rules: ownership chain, `in_progress` requirement, idempotent
/// row insert, exactly one `before_photo_captured` event whose `occurred_at`
/// is the ORIGINAL capture time.
class _ServerLikeFilesRemote implements JobFilesRemoteDataSource {
  _ServerLikeFilesRemote({
    required Map<String, _RemoteJob> jobs,
    required this.authorizedEmployeeId,
    this.isAdmin = false,
  })
    // ignore: prefer_initializing_formals — private field, public parameter.
    : _jobs = jobs;

  final Map<String, _RemoteJob> _jobs;

  /// The employee row the signed-in user owns (`auth.uid()` → employee).
  final String? authorizedEmployeeId;

  /// Active-admin sessions bypass the assignment check (as the RPC does).
  final bool isAdmin;

  /// Toggle to simulate a Storage outage.
  bool failUploads = false;

  int uploadCalls = 0;
  int registerCalls = 0;

  /// Storage objects by path (upsert semantics: same path overwrites).
  final Map<String, List<int>> objects = <String, List<int>>{};

  /// `job_files` rows by file id.
  final Map<String, Map<String, Object?>> files =
      <String, Map<String, Object?>>{};

  /// The `job_events` rows the server appended.
  final List<Map<String, Object?>> events = <Map<String, Object?>>[];

  void _assertAuthorized(String jobId) {
    final _RemoteJob? job = _jobs[jobId];
    if (job == null) {
      throw StateError('Job not found.');
    }
    if (!isAdmin && job.assignedEmployeeId != authorizedEmployeeId) {
      // The storage policies / RPC refuse other technicians' jobs.
      throw StateError('This job is not assigned to you.');
    }
  }

  @override
  Future<List<JobFile>> getJobBeforePhotos(String jobId) async {
    return files.values
        .where(
          (Map<String, Object?> f) =>
              f['job_id'] == jobId && f['file_type'] == 'before',
        )
        .map(
          (Map<String, Object?> f) => JobFile(
            id: f['id']! as String,
            jobId: f['job_id']! as String,
            fileType: f['file_type']! as String,
            fileName: f['file_name']! as String,
            mimeType: f['mime_type'] as String?,
            sizeBytes: f['size_bytes'] as int?,
            capturedAt: f['captured_at']! as DateTime,
            remotePath: f['storage_path']! as String,
            syncState: JobFileSyncState.synced,
          ),
        )
        .toList();
  }

  @override
  Future<void> uploadPhotoBytes({
    required String storagePath,
    required List<int> bytes,
    String? mimeType,
  }) async {
    if (failUploads) {
      throw const SocketException('Simulated storage outage.');
    }
    uploadCalls++;
    // Storage policies: only objects of an authorized job's path.
    _assertAuthorized(storagePath.split('/')[1]);
    objects[storagePath] = bytes; // upsert: same path → same object
  }

  @override
  Future<void> registerJobFile({
    required String fileId,
    required String jobId,
    required String fileType,
    required String storagePath,
    required String fileName,
    String? mimeType,
    int? sizeBytes,
    required DateTime capturedAt,
  }) async {
    registerCalls++;
    _assertAuthorized(jobId);

    final Map<String, Object?>? existing = files[fileId];
    if (existing != null) {
      // Replay: same file id must belong to the same job; nothing changes —
      // no duplicate row, no duplicate event.
      if (existing['job_id'] != jobId) {
        throw StateError('This file id is already registered to another job.');
      }
      return;
    }

    final _RemoteJob job = _jobs[jobId]!;
    if (fileType == 'before' && job.status != JobStatus.inProgress) {
      throw StateError(
        'Before photos can only be added to a job that is in progress.',
      );
    }

    files[fileId] = <String, Object?>{
      'id': fileId,
      'job_id': jobId,
      'employee_id': authorizedEmployeeId,
      'file_type': fileType,
      'storage_path': storagePath,
      'file_name': fileName,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
      // The ORIGINAL capture time — never replaced by the upload time.
      'captured_at': capturedAt,
    };

    if (fileType == 'before') {
      events.add(<String, Object?>{
        'job_id': jobId,
        'employee_id': authorizedEmployeeId,
        'event_type': 'before_photo_captured',
        'occurred_at': capturedAt,
      });
    }
  }

  @override
  Future<Uint8List> downloadPhotoBytes(String storagePath) async {
    return Uint8List.fromList(objects[storagePath]!);
  }
}

/// These tests exercise the file path only; the jobs RPC surface must never
/// be reached (and would need a Supabase client).
class _UnusedJobsRemote implements JobsRemoteDataSource {
  @override
  Future<List<Job>> getJobs() async => throw UnimplementedError();

  @override
  Future<Job> getJobById(String id) async => throw UnimplementedError();

  @override
  Future<void> updateJobStatus({
    required String jobId,
    required String status,
  }) async => throw UnimplementedError();

  @override
  Future<JobCustomerInfo?> getJobCustomerInfo(String jobId) async =>
      throw UnimplementedError();

  @override
  Future<Job> startJob(String jobId) async => throw UnimplementedError();
}

/// The server-side facts a job carries for these tests.
class _RemoteJob {
  const _RemoteJob({
    required this.assignedEmployeeId,
    required this.status,
  });

  final String? assignedEmployeeId;
  final String status;
}

class _SwitchableNetworkInfo implements NetworkInfo {
  final StreamController<bool> _controller =
      StreamController<bool>.broadcast();
  bool _online = false;

  @override
  Future<bool> get isConnected async => _online;

  @override
  Stream<bool> get onConnectionChanged => _controller.stream;

  void setOnline(bool value) {
    _online = value;
    _controller.add(value);
  }

  Future<void> close() => _controller.close();
}

void main() {
  late AppTestHarness app;
  late Directory tempDir;

  setUp(() async {
    app = AppTestHarness();
    tempDir = await Directory.systemTemp.createTemp('before_photos_sync');
  });

  tearDown(() async {
    await app.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Boots the REAL offline stack and swaps only the remote surfaces.
  /// Returns the fake backend for assertions.
  Future<_ServerLikeFilesRemote> configureSync({
    required bool online,
    required Map<String, _RemoteJob> jobs,
    String? authorizedEmployeeId = 'emp-me',
    bool isAdmin = false,
  }) async {
    await app.configure(
      user: technicianUser,
      withJobsSync: true,
      jobsOnline: online,
    );

    // The jobs RPC data source is not under test here — swap it before the
    // repository is first constructed so no Supabase client is ever needed.
    await sl.unregister<JobsRemoteDataSource>();
    sl.registerSingleton<JobsRemoteDataSource>(_UnusedJobsRemote());

    // App-owned storage rooted in a temp directory (stable local copies).
    await sl.unregister<FileStorage>();
    sl.registerSingleton<FileStorage>(AppFileStorage(baseDirectory: tempDir));

    await sl.unregister<LocalFileStorage>();
    sl.registerSingleton<LocalFileStorage>(
      LocalFileStorage(
        fileStorage: sl<FileStorage>(),
        database: sl<AppDatabase>(),
        syncQueue: sl<SyncQueue>(),
      ),
    );

    final _ServerLikeFilesRemote remote = _ServerLikeFilesRemote(
      jobs: jobs,
      authorizedEmployeeId: authorizedEmployeeId,
      isAdmin: isAdmin,
    );
    await sl.unregister<JobFilesRemoteDataSource>();
    sl.registerSingleton<JobFilesRemoteDataSource>(remote);
    return remote;
  }

  /// Writes a stand-in camera capture outside app storage (a temp path the
  /// OS could clean up at any time).
  File capturedPhoto(String name) {
    final Directory cameraTemp = Directory.systemTemp.createTempSync('cam');
    return writeTempPhoto(cameraTemp, name);
  }

  Future<void> waitUntil(Future<bool> Function() condition) async {
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      if (await condition()) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('Condition was not met within 10s.');
  }

  Future<void> untilQueueDrained() => waitUntil(() async {
    return await sl<SyncQueue>().pendingCount() == 0 &&
        sl<SyncManager>().isSyncing == false;
  });

  // 11 / 10 / 12 / 8 — offline capture: durable queue entry, stable local
  // copy, immediately available, nothing pushed.
  test('offline capture queues one durable upload and keeps a stable copy', () async {
    final _ServerLikeFilesRemote remote = await configureSync(
      online: false,
      jobs: const <String, _RemoteJob>{
        'job-mine': _RemoteJob(
          assignedEmployeeId: 'emp-me',
          status: JobStatus.inProgress,
        ),
      },
    );

    final File source = capturedPhoto('shot.png');
    final String fileId = await sl<JobsRepository>().addBeforePhoto(
      jobId: 'job-mine',
      pickedFilePath: source.path,
    );

    // The local row exists with an AUTOMATIC capture timestamp, pending.
    final LocalJobFile? row = await sl<LocalFileStorage>().getFile(fileId);
    expect(row, isNotNull);
    expect(row!.jobId, 'job-mine');
    expect(row.fileType, 'before');
    expect(row.syncStatus, 'pending');
    expect(row.remotePath, isNull);
    expect(row.localPath, startsWith('before/'));
    expect(row.capturedAt, isNotNull);

    // The bytes were copied into app-owned storage; the temporary camera
    // file may vanish without losing the photo.
    expect(await sl<FileStorage>().exists(row.localPath), isTrue);
    await source.delete();
    expect(await sl<FileStorage>().exists(row.localPath), isTrue);

    // Exactly one durable queue entry for this file.
    expect(await sl<SyncQueue>().pendingCount(), 1);
    final SyncOperation? op = await sl<SyncQueue>().nextPending();
    expect(op, isNotNull);
    expect(op!.entityType, SyncEntityType.jobFile);
    expect(op.entityId, fileId);
    expect(op.type, SyncOperationType.upload);

    // Offline, the photo is still visible immediately (local-first).
    final List<JobFile> visible = await sl<JobsRepository>().getBeforePhotos(
      'job-mine',
    );
    expect(visible, hasLength(1));
    expect(visible.single.id, fileId);
    expect(visible.single.capturedAt, row.capturedAt);

    // Nothing reached the backend while offline.
    expect(remote.uploadCalls, 0);
    expect(remote.registerCalls, 0);
    expect(remote.events, isEmpty);
  });

  // 13 / 14 / 15 / 9 — reconnection uploads, registers, appends the event;
  // the ORIGINAL capture timestamp survives the whole path.
  test('reconnect uploads the photo, registers it and appends one event', () async {
    final _ServerLikeFilesRemote remote = await configureSync(
      online: false,
      jobs: const <String, _RemoteJob>{
        'job-mine': _RemoteJob(
          assignedEmployeeId: 'emp-me',
          status: JobStatus.inProgress,
        ),
      },
    );

    final _SwitchableNetworkInfo network = _SwitchableNetworkInfo();
    await sl.unregister<NetworkInfo>();
    sl.registerSingleton<NetworkInfo>(network);
    await sl<SyncManager>().start();

    final File source = capturedPhoto('shot.png');
    final String fileId = await sl<JobsRepository>().addBeforePhoto(
      jobId: 'job-mine',
      pickedFilePath: source.path,
    );
    final LocalJobFile row =
        (await sl<LocalFileStorage>().getFile(fileId))!;
    final DateTime originalCapturedAt = row.capturedAt;
    expect(remote.uploadCalls, 0);

    // Let some time pass so "upload time" would differ from capture time.
    await Future<void>.delayed(const Duration(milliseconds: 40));

    // Internet returns: the engine drains the queue on its own.
    network.setOnline(true);
    await untilQueueDrained();

    expect(await sl<SyncQueue>().pendingCount(), 0);
    expect(await sl<SyncQueue>().failedCount(), 0);

    // Storage: exactly one object at the deterministic, id-based path.
    expect(remote.uploadCalls, 1);
    final String expectedPath = 'jobs/job-mine/before/$fileId.png';
    expect(remote.objects.keys, <String>[expectedPath]);
    expect(remote.objects[expectedPath], kTestPhotoBytes);

    // job_files record: correct job, type, path — and the ORIGINAL capture
    // time (not the later upload time).
    expect(remote.registerCalls, 1);
    final Map<String, Object?> stored = remote.files[fileId]!;
    expect(stored['job_id'], 'job-mine');
    expect(stored['file_type'], 'before');
    expect(stored['storage_path'], expectedPath);
    expect(stored['employee_id'], 'emp-me');
    expect(stored['captured_at'], originalCapturedAt);

    // Exactly one event, stamped with the capture time.
    expect(remote.events, hasLength(1));
    expect(remote.events.single['event_type'], 'before_photo_captured');
    expect(remote.events.single['job_id'], 'job-mine');
    expect(remote.events.single['employee_id'], 'emp-me');
    expect(remote.events.single['occurred_at'], originalCapturedAt);

    // Local row reconciled: synced + remote path recorded.
    final LocalJobFile after = (await sl<LocalFileStorage>().getFile(fileId))!;
    expect(after.syncStatus, 'synced');
    expect(after.remotePath, expectedPath);
    expect(after.capturedAt, originalCapturedAt);

    await network.close();
  });

  // 16 — retries/lost-ack replays never duplicate the object, row or event.
  test('replayed pushes stay idempotent: one object, one row, one event', () async {
    final _ServerLikeFilesRemote remote = await configureSync(
      online: false,
      jobs: const <String, _RemoteJob>{
        'job-mine': _RemoteJob(
          assignedEmployeeId: 'emp-me',
          status: JobStatus.inProgress,
        ),
      },
    );

    final File source = capturedPhoto('shot.jpg');
    final String fileId = await sl<JobsRepository>().addBeforePhoto(
      jobId: 'job-mine',
      pickedFilePath: source.path,
    );
    final SyncOperation op = (await sl<SyncQueue>().nextPending())!;

    // Simulate the same operation being pushed three times (lost ack /
    // retry storm): the stable file id keeps everything singular.
    final SyncOperationHandler handler =
        sl<SyncHandlerRegistry>().handlerFor(SyncEntityType.jobFile)!;
    for (int i = 0; i < 3; i++) {
      final RemotePushResult result = await handler.push(op);
      expect(result.success, isTrue, reason: 'push #$i should succeed');
    }

    expect(remote.objects, hasLength(1));
    expect(remote.files, hasLength(1));
    expect(remote.events, hasLength(1));
    expect(remote.events.single['event_type'], 'before_photo_captured');
    // The local row is synced after the first confirmed push.
    final LocalJobFile row = (await sl<LocalFileStorage>().getFile(fileId))!;
    expect(row.syncStatus, 'synced');
  });

  // 17 — Storage failure: operation stays retryable, nothing is lost; the
  // Retry path (existing SyncProcessor) completes it afterwards.
  test('upload failure keeps the photo pending until a retry succeeds', () async {
    final _ServerLikeFilesRemote remote = await configureSync(
      online: false,
      jobs: const <String, _RemoteJob>{
        'job-mine': _RemoteJob(
          assignedEmployeeId: 'emp-me',
          status: JobStatus.inProgress,
        ),
      },
    );

    final _SwitchableNetworkInfo network = _SwitchableNetworkInfo();
    await sl.unregister<NetworkInfo>();
    sl.registerSingleton<NetworkInfo>(network);
    await sl<SyncManager>().start();

    remote.failUploads = true;
    network.setOnline(true);

    final File source = capturedPhoto('shot.png');
    final String fileId = await sl<JobsRepository>().addBeforePhoto(
      jobId: 'job-mine',
      pickedFilePath: source.path,
    );

    await waitUntil(() async => await sl<SyncQueue>().failedCount() == 1);
    expect(remote.registerCalls, 0);
    expect(remote.events, isEmpty);

    // Local copy untouched: the photo is still pending and still readable.
    final LocalJobFile failedRow =
        (await sl<LocalFileStorage>().getFile(fileId))!;
    expect(failedRow.syncStatus, 'pending');
    expect(await sl<FileStorage>().exists(failedRow.localPath), isTrue);

    // Storage recovers; the existing retry mechanism drains the queue.
    remote.failUploads = false;
    await sl<SyncProcessor>().retryFailedOperations();
    await untilQueueDrained();

    expect(await sl<SyncQueue>().failedCount(), 0);
    // The failed attempt threw before counting; the retry is the one counted.
    expect(remote.uploadCalls, 1);
    expect(remote.files, hasLength(1));
    expect(remote.events, hasLength(1)); // still exactly ONE event

    final LocalJobFile row = (await sl<LocalFileStorage>().getFile(fileId))!;
    expect(row.syncStatus, 'synced');

    await network.close();
  });

  // 18 — authorization is enforced server-side at sync time: another
  // technician's job accepts neither the object nor the registration.
  test('uploads to another technician\'s job are refused by the server', () async {
    final _ServerLikeFilesRemote remote = await configureSync(
      online: false,
      jobs: const <String, _RemoteJob>{
        'job-other': _RemoteJob(
          assignedEmployeeId: 'emp-somebody-else',
          status: JobStatus.inProgress,
        ),
      },
    );

    final _SwitchableNetworkInfo network = _SwitchableNetworkInfo();
    await sl.unregister<NetworkInfo>();
    sl.registerSingleton<NetworkInfo>(network);
    await sl<SyncManager>().start();
    network.setOnline(true);

    final File source = capturedPhoto('shot.png');
    final String fileId = await sl<JobsRepository>().addBeforePhoto(
      jobId: 'job-other',
      pickedFilePath: source.path,
    );

    await waitUntil(() async => await sl<SyncQueue>().failedCount() == 1);

    // Storage policy refused the object; the RPC was never reached.
    expect(remote.uploadCalls, 1);
    expect(remote.objects, isEmpty);
    expect(remote.registerCalls, 0);
    expect(remote.files, isEmpty);
    expect(remote.events, isEmpty);

    // The local copy survives as `pending` — never fake-synced.
    final LocalJobFile row = (await sl<LocalFileStorage>().getFile(fileId))!;
    expect(row.syncStatus, 'pending');

    await network.close();
  });

  // 5 (server side) — a job that is not in_progress refuses before photos,
  // even if a capture was queued for it.
  test('the server refuses before photos for jobs not in progress', () async {
    final _ServerLikeFilesRemote remote = await configureSync(
      online: false,
      jobs: const <String, _RemoteJob>{
        'job-mine': _RemoteJob(
          assignedEmployeeId: 'emp-me',
          status: JobStatus.assigned, // not started yet
        ),
      },
    );

    final _SwitchableNetworkInfo network = _SwitchableNetworkInfo();
    await sl.unregister<NetworkInfo>();
    sl.registerSingleton<NetworkInfo>(network);
    await sl<SyncManager>().start();
    network.setOnline(true);

    final File source = capturedPhoto('shot.png');
    await sl<JobsRepository>().addBeforePhoto(
      jobId: 'job-mine',
      pickedFilePath: source.path,
    );

    await waitUntil(() async => await sl<SyncQueue>().failedCount() == 1);

    expect(remote.registerCalls, 1); // attempted…
    expect(remote.files, isEmpty); // …but refused
    expect(remote.events, isEmpty); // no event for a refused photo

    await network.close();
  });

  // 6 (server side) — admins may register for jobs they do not own.
  test('admin sessions can register before photos for any job', () async {
    final _ServerLikeFilesRemote remote = await configureSync(
      online: false,
      jobs: const <String, _RemoteJob>{
        'job-tech': _RemoteJob(
          assignedEmployeeId: 'emp-tech-1',
          status: JobStatus.inProgress,
        ),
      },
      authorizedEmployeeId: 'emp-admin',
      isAdmin: true,
    );

    final File source = capturedPhoto('shot.png');
    final String fileId = await sl<JobsRepository>().addBeforePhoto(
      jobId: 'job-tech',
      pickedFilePath: source.path,
    );

    final SyncOperationHandler handler =
        sl<SyncHandlerRegistry>().handlerFor(SyncEntityType.jobFile)!;
    final RemotePushResult result = await handler.push(
      (await sl<SyncQueue>().nextPending())!,
    );

    expect(result.success, isTrue);
    expect(remote.files, hasLength(1));
    expect(remote.files[fileId]!['employee_id'], 'emp-admin');
    expect(remote.events, hasLength(1));
  });
}
