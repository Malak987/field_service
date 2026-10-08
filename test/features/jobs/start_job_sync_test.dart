import 'dart:async';

import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/network/connectivity_service.dart';
import 'package:field_service/core/network/network_info.dart';
import 'package:field_service/core/sync/sync_manager.dart';
import 'package:field_service/core/sync/sync_operation.dart';
import 'package:field_service/core/sync/sync_processor.dart';
import 'package:field_service/core/sync/sync_queue.dart';

import 'dart:typed_data';

import 'package:field_service/features/jobs/data/datasources/job_files_remote_data_source.dart';
import 'package:field_service/features/jobs/data/datasources/jobs_remote_data_source.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';

/// Server-side clock of the fake backend: the ONLY source of `started_at`.
final DateTime _serverNow = DateTime.utc(2026, 10, 6, 9, 30);

Job _job({
  required String id,
  required int number,
  String? assignedEmployeeId,
  String status = JobStatus.assigned,
}) {
  return Job(
    id: id,
    jobNumber: number,
    customerId: 'cust-$id',
    assignedEmployeeId: assignedEmployeeId,
    jobType: 'kitchen_renovation',
    status: JobStatus(status),
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
    expiresAt: DateTime.utc(2026, 12, 1),
  );
}

/// Fake of the `start_job` RPC endpoint with the SAME semantics as the
/// corrected SQL (job_workflow_permissions_setup.sql): role + ownership
/// check → duplicate-start protection → atomic update + event.
class _ServerLikeJobsRemote implements JobsRemoteDataSource {
  _ServerLikeJobsRemote({
    required Map<String, Job> jobs,
    required this.authorizedEmployeeId,
    this.isAdmin = false,
  })
    // ignore: prefer_initializing_formals — private field, public parameter.
    : _jobs = jobs;

  final Map<String, Job> _jobs;

  /// The employee row the signed-in user owns (`auth.uid()` → employee).
  final String? authorizedEmployeeId;

  /// The caller's session is an admin. Business-rule correction: admins are
  /// REFUSED by `start_job` — they create/assign/monitor jobs but never
  /// execute them, even by calling the RPC directly.
  final bool isAdmin;

  /// How many times the RPC was invoked (attempts, incl. retries).
  int startCalls = 0;

  /// The `job_events` rows the server appended.
  final List<Map<String, Object?>> events = <Map<String, Object?>>[];

  Job jobById(String id) => _jobs[id]!;

  @override
  Future<List<Job>> getJobs() async => _jobs.values.toList();

  @override
  Future<Job> getJobById(String id) async {
    final Job? job = _jobs[id];
    if (job == null) {
      throw StateError('Job not found: $id');
    }
    return job;
  }

  @override
  Future<JobCustomerInfo?> getJobCustomerInfo(String jobId) async => null;

  @override
  Future<void> updateJobStatus({
    required String jobId,
    required String status,
  }) async => throw UnimplementedError();

  @override
  Future<Job> createJob({
    required String customerId,
    required String jobType,
    String? description,
    required String assignedEmployeeId,
  }) async => throw UnimplementedError();

  @override
  Future<Job> saveWorkDescription({
    required String jobId,
    required String workDescription,
  }) async => throw UnimplementedError();

  @override
  Future<Job> startJob(String jobId) async {
    startCalls++;
    final Job? job = _jobs[jobId];
    if (job == null) {
      throw StateError('Job not found.');
    }
    // Role: ONLY an active technician may start a job. Admins are refused
    // outright — the corrected RPC's most important rule.
    if (isAdmin) {
      throw StateError('Only the assigned technician can start this job.');
    }
    // Ownership: only the job's own assigned employee (an unassigned job
    // never matches).
    if (job.assignedEmployeeId != authorizedEmployeeId) {
      throw StateError('This job is not assigned to you.');
    }
    // Duplicate-start protection: already in_progress → succeed unchanged
    // (no second event, started_at untouched) — idempotent replays.
    if (job.status.value == JobStatus.inProgress) {
      return job;
    }
    if (job.status.value != JobStatus.assigned) {
      throw StateError(
        'Job cannot be started from status "${job.status.value}".',
      );
    }

    final Job started = job.copyWith(
      status: const JobStatus(JobStatus.inProgress),
      startedAt: _serverNow,
      updatedAt: _serverNow,
    );
    _jobs[jobId] = started;
    events.add(<String, Object?>{
      'job_id': jobId,
      'employee_id': authorizedEmployeeId,
      'event_type': 'job_started',
      'occurred_at': _serverNow,
    });
    return started;
  }

  @override
  Future<Job> completeJob(String jobId) async => throw UnimplementedError();
}

void main() {
  late AppTestHarness app;

  setUp(() => app = AppTestHarness());
  tearDown(() => app.dispose());

  /// Configures the harness with the REAL jobs repository + durable Drift
  /// sync queue and swaps only the remote data source for the fake RPC.
  Future<_ServerLikeJobsRemote> configureSync({
    required bool online,
    required Map<String, Job> jobs,
    String? authorizedEmployeeId = 'emp-me',
    bool isAdmin = false,
  }) async {
    await app.configure(
      user: technicianUser,
      withJobsSync: true,
      jobsOnline: online,
    );
    final _ServerLikeJobsRemote remote = _ServerLikeJobsRemote(
      jobs: jobs,
      authorizedEmployeeId: authorizedEmployeeId,
      isAdmin: isAdmin,
    );
    await sl.unregister<JobsRemoteDataSource>();
    sl.registerSingleton<JobsRemoteDataSource>(remote);

    // The job-files surface is not under test here — swap it so the
    // repository construction never needs a Supabase client.
    await sl.unregister<JobFilesRemoteDataSource>();
    sl.registerSingleton<JobFilesRemoteDataSource>(_UnusedFilesRemote());
    return remote;
  }

  test(
    'offline start queues one durable operation and pushes nothing',
    () async {
      final _ServerLikeJobsRemote remote = await configureSync(
        online: false,
        jobs: <String, Job>{
          'job-mine': _job(
            id: 'job-mine',
            number: 101,
            assignedEmployeeId: 'emp-me',
          ),
        },
      );

      // Pressing Start while offline succeeds locally...
      await sl<JobsRepository>().startJob('job-mine');

      // ...and persists EXACTLY one operation in the existing queue.
      expect(await sl<SyncQueue>().pendingCount(), 1);
      expect(await sl<SyncQueue>().failedCount(), 0);
      final SyncOperation? op = await sl<SyncQueue>().nextPending();
      expect(op, isNotNull);
      expect(op!.entityType, SyncEntityType.job);
      expect(op.entityId, 'job-mine');
      expect(op.type, SyncOperationType.update);
      expect(op.payload['action'], 'start_job');
      // No timestamp ever leaves the client.
      expect(op.payload.containsKey('started_at'), isFalse);

      // Nothing reached the server while offline.
      expect(remote.startCalls, 0);
      expect(remote.jobById('job-mine').status.value, JobStatus.assigned);

      // The duplicate guard refuses a second start while one is queued.
      await expectLater(
        () => sl<JobsRepository>().startJob('job-mine'),
        throwsA(isA<JobAlreadyStartedException>()),
      );
      expect(await sl<SyncQueue>().pendingCount(), 1);
    },
  );

  test(
    'queued offline start syncs automatically when connectivity returns',
    () async {
      final _ServerLikeJobsRemote remote = await configureSync(
        online: false,
        jobs: <String, Job>{
          'job-mine': _job(
            id: 'job-mine',
            number: 101,
            assignedEmployeeId: 'emp-me',
          ),
        },
      );

      // Swap in a switchable network probe BEFORE the connectivity service is
      // built, then start the real sync engine exactly like `main()` does.
      final _SwitchableNetworkInfo network = _SwitchableNetworkInfo();
      await sl.unregister<NetworkInfo>();
      sl.registerSingleton<NetworkInfo>(network);
      await sl<SyncManager>().start();

      await sl<JobsRepository>().startJob('job-mine');
      expect(remote.startCalls, 0);
      expect(await sl<SyncQueue>().pendingCount(), 1);

      // Internet returns: the engine's own connectivity listener must drain
      // the queue — no manual trigger.
      network.setOnline(true);
      await _untilQueueDrained();

      expect(await sl<SyncQueue>().pendingCount(), 0);
      expect(await sl<SyncQueue>().failedCount(), 0);
      expect(remote.startCalls, 1);
      expect(remote.events, hasLength(1));
      expect(remote.events.single['event_type'], 'job_started');
      expect(remote.events.single['job_id'], 'job-mine');
      expect(remote.events.single['employee_id'], 'emp-me');
      expect(remote.events.single['occurred_at'], _serverNow);
      // Authoritative server timestamp applied by the database, not the client.
      expect(remote.jobById('job-mine').status.value, JobStatus.inProgress);
      expect(remote.jobById('job-mine').startedAt, _serverNow);

      await network.close();
    },
  );

  test(
    'sync retries are idempotent: one event, started_at never reset',
    () async {
      final _ServerLikeJobsRemote remote = await configureSync(
        online: true,
        jobs: <String, Job>{
          'job-mine': _job(
            id: 'job-mine',
            number: 101,
            assignedEmployeeId: 'emp-me',
          ),
        },
      );
      await sl<ConnectivityService>().start();

      await sl<JobsRepository>().startJob('job-mine');
      await sl<SyncProcessor>().processPendingOperations();
      await _untilQueueDrained();
      expect(await sl<SyncQueue>().pendingCount(), 0);
      expect(remote.startCalls, 1);
      expect(remote.events, hasLength(1));

      // Replay the same logical change (a push that succeeded but whose
      // queue row was never marked synced — crash / lost ack).
      await sl<SyncQueue>().enqueue(
        SyncOperation(
          id: 'replay-op',
          entityType: SyncEntityType.job,
          entityId: 'job-mine',
          type: SyncOperationType.update,
          payload: <String, Object?>{'action': 'start_job'},
          createdAt: DateTime.utc(2026, 10, 6, 10),
        ),
      );
      await sl<SyncProcessor>().processPendingOperations();
      await _untilQueueDrained();

      // Second attempt accepted, nothing duplicated, nothing reset.
      expect(await sl<SyncQueue>().pendingCount(), 0);
      expect(await sl<SyncQueue>().failedCount(), 0);
      expect(remote.startCalls, 2);
      expect(remote.events, hasLength(1));
      expect(remote.jobById('job-mine').startedAt, _serverNow);
      expect(remote.jobById('job-mine').status.value, JobStatus.inProgress);
    },
  );

  test('re-enqueue with the same operation id is a no-op', () async {
    await configureSync(
      online: false,
      jobs: <String, Job>{
        'job-mine': _job(
          id: 'job-mine',
          number: 101,
          assignedEmployeeId: 'emp-me',
        ),
      },
    );

    final SyncOperation op = SyncOperation(
      id: 'fixed-op-id',
      entityType: SyncEntityType.job,
      entityId: 'job-mine',
      type: SyncOperationType.update,
      payload: <String, Object?>{'action': 'start_job'},
      createdAt: DateTime.utc(2026, 10, 6, 9),
    );
    await sl<SyncQueue>().enqueue(op);
    await sl<SyncQueue>().enqueue(op); // duplicate enqueue

    expect(await sl<SyncQueue>().pendingCount(), 1);
  });

  test(
    'start refused by the server stays failed and retryable, never synced',
    () async {
      // Not the assigned employee (covers "another technician's job" and
      // "unassigned job" at the sync layer — the RPC refuses both).
      final _ServerLikeJobsRemote remote = await configureSync(
        online: true,
        jobs: <String, Job>{
          'job-other': _job(
            id: 'job-other',
            number: 102,
            assignedEmployeeId: 'emp-somebody-else',
          ),
        },
      );
      await sl<ConnectivityService>().start();

      await sl<JobsRepository>().startJob('job-other');
      await sl<SyncProcessor>().processPendingOperations();
      await _untilQueueDrained();

      expect(remote.startCalls, 1);
      expect(remote.events, isEmpty);
      expect(remote.jobById('job-other').status.value, JobStatus.assigned);
      expect(await sl<SyncQueue>().pendingCount(), 0);
      expect(await sl<SyncQueue>().failedCount(), 1);

      // The job itself never changed: no status flip, no started_at.
      expect(remote.jobById('job-other').startedAt, isNull);
    },
  );

  test(
    'backend rejects an admin Start Job attempt (admins never execute jobs)',
    () async {
      final _ServerLikeJobsRemote remote = await configureSync(
        online: true,
        jobs: <String, Job>{
          'job-any': _job(
            id: 'job-any',
            number: 103,
            assignedEmployeeId: 'emp-somebody-else',
          ),
        },
        authorizedEmployeeId: 'emp-admin',
        isAdmin: true,
      );
      await sl<ConnectivityService>().start();

      await sl<JobsRepository>().startJob('job-any');
      await sl<SyncProcessor>().processPendingOperations();
      await _untilQueueDrained();

      // The RPC was reached and refused: the operation stays retryable-failed
      // in the existing queue, and the job is completely untouched.
      expect(remote.startCalls, 1);
      expect(remote.events, isEmpty);
      expect(await sl<SyncQueue>().pendingCount(), 0);
      expect(await sl<SyncQueue>().failedCount(), 1);
      expect(remote.jobById('job-any').status.value, JobStatus.assigned);
      expect(remote.jobById('job-any').startedAt, isNull);
    },
  );
}

/// Network probe the test can flip offline ↔ online, so the real
/// `SyncManager` connectivity listener is what triggers the sync run.
/// Start Job tests never touch job files; the files surface must never be
/// reached (and would need a Supabase client).
class _UnusedFilesRemote implements JobFilesRemoteDataSource {
  @override
  Future<List<JobFile>> getJobFilesByType(
    String jobId,
    String fileType,
  ) async => throw UnimplementedError();

  @override
  Future<List<JobFile>> getJobBeforePhotos(String jobId) async =>
      throw UnimplementedError();

  @override
  Future<void> uploadPhotoBytes({
    required String storagePath,
    required List<int> bytes,
    String? mimeType,
  }) async => throw UnimplementedError();

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
  }) async => throw UnimplementedError();

  @override
  Future<Uint8List> downloadPhotoBytes(String storagePath) async =>
      throw UnimplementedError();
}

class _SwitchableNetworkInfo implements NetworkInfo {
  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  bool _connected = false;

  @override
  Future<bool> get isConnected async => _connected;

  @override
  Stream<bool> get onConnectionChanged => _controller.stream;

  void setOnline(bool value) {
    _connected = value;
    _controller.add(value);
  }

  Future<void> close() => _controller.close();
}

/// Waits (bounded) until the shared queue has drained.
Future<void> _untilQueueDrained() async {
  for (int i = 0; i < 200; i++) {
    if (await sl<SyncQueue>().pendingCount() == 0) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Sync queue did not drain in time.');
}
