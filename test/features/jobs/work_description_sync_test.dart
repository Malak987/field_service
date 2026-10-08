import 'dart:async';
import 'dart:typed_data';

import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/network/connectivity_service.dart';
import 'package:field_service/core/network/network_info.dart';
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

/// Server-side clock of the fake backend: the ONLY source of event times.
final DateTime _serverNow = DateTime.utc(2026, 10, 7, 10, 15);

Job _job({
  required String id,
  required int number,
  required String assignedEmployeeId,
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
    description: 'Customer wants the kitchen renovated.',
    workDescription: workDescription,
    status: JobStatus(status),
    startedAt: startedAt,
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
    expiresAt: DateTime.utc(2026, 12, 1),
  );
}

/// Fake of the `save_work_description` RPC with the SAME semantics as
/// `supabase/work_description_setup.sql`: authenticated → employee resolved
/// from the auth identity → role must be technician (admins refused) →
/// ownership → status must be `in_progress` → trim/validate → apply with
/// `IS DISTINCT FROM` idempotency (replaying the same text is a success
/// that creates NO second `work_description_added` event).
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

  /// The caller's session is an admin. Admins are REFUSED by the RPC — they
  /// monitor jobs but never write work descriptions, even via a direct call.
  final bool isAdmin;

  /// How many times the RPC was invoked (attempts, incl. retries).
  int saveCalls = 0;

  /// Parameters of the last invocation — the wire contract.
  Map<String, Object?>? lastRequest;

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
  Future<Job> startJob(String jobId) async => throw UnimplementedError();

  @override
  Future<Job> saveWorkDescription({
    required String jobId,
    required String workDescription,
  }) async {
    saveCalls++;
    lastRequest = <String, Object?>{
      'p_job_id': jobId,
      'p_work_description': workDescription,
    };

    final Job? job = _jobs[jobId];
    if (job == null) {
      throw StateError('Job not found.');
    }
    // Role: ONLY an active technician may save a work description. Admins
    // are refused outright — the RPC's most important rule.
    if (isAdmin) {
      throw StateError(
        'Only the assigned technician can update the work description.',
      );
    }
    // Ownership: only the job's own assigned employee.
    if (job.assignedEmployeeId != authorizedEmployeeId) {
      throw StateError('This job is not assigned to you.');
    }
    // Lifecycle: editable ONLY while in_progress.
    if (job.status.value != JobStatus.inProgress) {
      throw StateError(
        'Work description can only be added while the job is in progress.',
      );
    }
    // Server-side validation mirrors the client: trim, non-empty, max length.
    final String clean = workDescription.trim();
    if (clean.isEmpty) {
      throw StateError('Work description cannot be empty.');
    }
    if (clean.length > JobsRepository.maxWorkDescriptionLength) {
      throw StateError('Work description is too long.');
    }
    // Idempotency (IS DISTINCT FROM): replaying the already-stored text is
    // a success that creates NO second event and touches no timestamp.
    if (job.workDescription == clean) {
      return job;
    }

    final Job updated = job.copyWith(
      workDescription: clean,
      updatedAt: _serverNow,
    );
    _jobs[jobId] = updated;
    events.add(<String, Object?>{
      'job_id': jobId,
      'employee_id': authorizedEmployeeId,
      'event_type': 'work_description_added',
      'occurred_at': _serverNow,
    });
    return updated;
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

  Map<String, Job> inProgressJob() => <String, Job>{
    'job-mine': _job(
      id: 'job-mine',
      number: 101,
      assignedEmployeeId: 'emp-me',
      startedAt: DateTime.utc(2026, 10, 6, 9, 30),
    ),
  };

  test(
    'offline save queues one durable operation; reconnect syncs with ONE event',
    () async {
      final _ServerLikeJobsRemote remote = await configureSync(
        online: false,
        jobs: inProgressJob(),
      );

      // Swap in a switchable network probe BEFORE the connectivity service is
      // built, then start the real sync engine exactly like `main()` does.
      final _SwitchableNetworkInfo network = _SwitchableNetworkInfo();
      await sl.unregister<NetworkInfo>();
      sl.registerSingleton<NetworkInfo>(network);
      await sl<SyncManager>().start();

      // Saving while offline succeeds locally (trimmed)...
      await sl<JobsRepository>().saveWorkDescription(
        jobId: 'job-mine',
        workDescription: '  Installed the new countertop.  ',
      );

      // ...and persists EXACTLY one operation in the existing queue. The
      // trimmed text travels in the payload — the queue row doubles as the
      // durable local copy while offline.
      expect(await sl<SyncQueue>().pendingCount(), 1);
      expect(await sl<SyncQueue>().failedCount(), 0);
      final SyncOperation? op = await sl<SyncQueue>().nextPending();
      expect(op, isNotNull);
      expect(op!.entityType, SyncEntityType.job);
      expect(op.entityId, 'job-mine');
      expect(op.type, SyncOperationType.update);
      expect(op.payload['action'], 'save_work_description');
      expect(op.payload['work_description'], 'Installed the new countertop.');
      // The payload carries NOTHING else: no employee id, no timestamp.
      expect(op.payload.keys.toSet(), <String>{'action', 'work_description'});

      // Nothing reached the server while offline.
      expect(remote.saveCalls, 0);
      expect(remote.jobById('job-mine').workDescription, isNull);

      // Internet returns: the engine's own connectivity listener must drain
      // the queue — no manual trigger.
      network.setOnline(true);
      await _untilQueueDrained();

      expect(await sl<SyncQueue>().pendingCount(), 0);
      expect(await sl<SyncQueue>().failedCount(), 0);
      expect(remote.saveCalls, 1);
      expect(remote.lastRequest, <String, Object?>{
        'p_job_id': 'job-mine',
        'p_work_description': 'Installed the new countertop.',
      });
      // Exactly one `work_description_added` event, server-stamped.
      expect(remote.events, hasLength(1));
      expect(remote.events.single['event_type'], 'work_description_added');
      expect(remote.events.single['job_id'], 'job-mine');
      expect(remote.events.single['employee_id'], 'emp-me');
      expect(remote.events.single['occurred_at'], _serverNow);
      // The stored text is separate from the admin's customer request.
      expect(
        remote.jobById('job-mine').workDescription,
        'Installed the new countertop.',
      );
      expect(
        remote.jobById('job-mine').description,
        'Customer wants the kitchen renovated.',
      );
      expect(remote.jobById('job-mine').updatedAt, _serverNow);

      await network.close();
    },
  );

  test(
    'replaying the same text is idempotent: second push, NO second event',
    () async {
      final _ServerLikeJobsRemote remote = await configureSync(
        online: true,
        jobs: inProgressJob(),
      );
      await sl<ConnectivityService>().start();

      await sl<JobsRepository>().saveWorkDescription(
        jobId: 'job-mine',
        workDescription: 'Fixed the sink.',
      );
      await sl<SyncProcessor>().processPendingOperations();
      await _untilQueueDrained();
      expect(await sl<SyncQueue>().pendingCount(), 0);
      expect(remote.saveCalls, 1);
      expect(remote.events, hasLength(1));

      // Replay the same logical save (a push that succeeded but whose queue
      // row was never marked synced — crash / lost ack).
      await sl<SyncQueue>().enqueue(
        SyncOperation(
          id: 'replay-op',
          entityType: SyncEntityType.job,
          entityId: 'job-mine',
          type: SyncOperationType.update,
          payload: <String, Object?>{
            'action': 'save_work_description',
            'work_description': 'Fixed the sink.',
          },
          createdAt: DateTime.utc(2026, 10, 7, 10),
        ),
      );
      await sl<SyncProcessor>().processPendingOperations();
      await _untilQueueDrained();

      // Second attempt accepted as a success — nothing duplicated.
      expect(await sl<SyncQueue>().pendingCount(), 0);
      expect(await sl<SyncQueue>().failedCount(), 0);
      expect(remote.saveCalls, 2);
      expect(remote.events, hasLength(1));
      expect(remote.jobById('job-mine').workDescription, 'Fixed the sink.');
    },
  );

  test(
    'changing the text later applies the latest value + exactly one new event',
    () async {
      final _ServerLikeJobsRemote remote = await configureSync(
        online: true,
        jobs: inProgressJob(),
      );
      await sl<ConnectivityService>().start();

      await sl<JobsRepository>().saveWorkDescription(
        jobId: 'job-mine',
        workDescription: 'First version.',
      );
      await sl<SyncProcessor>().processPendingOperations();
      await _untilQueueDrained();

      await sl<JobsRepository>().saveWorkDescription(
        jobId: 'job-mine',
        workDescription: 'Second, improved version.',
      );
      await sl<SyncProcessor>().processPendingOperations();
      await _untilQueueDrained();

      expect(await sl<SyncQueue>().failedCount(), 0);
      expect(remote.saveCalls, 2);
      expect(remote.events, hasLength(2));
      // Latest value wins — the existing conflict strategy, no new one.
      expect(
        remote.jobById('job-mine').workDescription,
        'Second, improved version.',
      );
      expect(
        remote.events.map((Map<String, Object?> e) => e['event_type']),
        everyElement('work_description_added'),
      );
      expect(
        remote.events.map((Map<String, Object?> e) => e['occurred_at']),
        everyElement(_serverNow),
      );
    },
  );

  test(
    'another technician\'s save is refused: retryable-failed, no event',
    () async {
      final _ServerLikeJobsRemote remote = await configureSync(
        online: true,
        jobs: <String, Job>{
          'job-other': _job(
            id: 'job-other',
            number: 102,
            assignedEmployeeId: 'emp-somebody-else',
            startedAt: DateTime.utc(2026, 10, 6, 9, 30),
          ),
        },
      );
      await sl<ConnectivityService>().start();

      await sl<JobsRepository>().saveWorkDescription(
        jobId: 'job-other',
        workDescription: 'Should not land.',
      );
      await sl<SyncProcessor>().processPendingOperations();
      await _untilQueueDrained();

      expect(remote.saveCalls, 1);
      expect(remote.events, isEmpty);
      expect(remote.jobById('job-other').workDescription, isNull);
      expect(await sl<SyncQueue>().pendingCount(), 0);
      expect(await sl<SyncQueue>().failedCount(), 1);
    },
  );

  test(
    'backend rejects an admin save attempt (admins never write work reports)',
    () async {
      final _ServerLikeJobsRemote remote = await configureSync(
        online: true,
        jobs: <String, Job>{
          'job-any': _job(
            id: 'job-any',
            number: 103,
            assignedEmployeeId: 'emp-somebody-else',
            startedAt: DateTime.utc(2026, 10, 6, 9, 30),
          ),
        },
        authorizedEmployeeId: 'emp-admin',
        isAdmin: true,
      );
      await sl<ConnectivityService>().start();

      await sl<JobsRepository>().saveWorkDescription(
        jobId: 'job-any',
        workDescription: 'Admin tries to write the report.',
      );
      await sl<SyncProcessor>().processPendingOperations();
      await _untilQueueDrained();

      // Refused by the RPC: retryable-failed, job completely untouched.
      expect(remote.saveCalls, 1);
      expect(remote.events, isEmpty);
      expect(remote.jobById('job-any').workDescription, isNull);
      expect(await sl<SyncQueue>().pendingCount(), 0);
      expect(await sl<SyncQueue>().failedCount(), 1);
    },
  );

  test('a job that was never started rejects the save', () async {
    final _ServerLikeJobsRemote remote = await configureSync(
      online: true,
      jobs: <String, Job>{
        'job-assigned': _job(
          id: 'job-assigned',
          number: 104,
          assignedEmployeeId: 'emp-me',
          status: JobStatus.assigned,
        ),
      },
    );
    await sl<ConnectivityService>().start();

    await sl<JobsRepository>().saveWorkDescription(
      jobId: 'job-assigned',
      workDescription: 'Too early.',
    );
    await sl<SyncProcessor>().processPendingOperations();
    await _untilQueueDrained();

    expect(remote.saveCalls, 1);
    expect(remote.events, isEmpty);
    expect(remote.jobById('job-assigned').workDescription, isNull);
    expect(await sl<SyncQueue>().failedCount(), 1);
  });

  test(
    'a completed job rejects the save — no edits after completion',
    () async {
      final _ServerLikeJobsRemote remote = await configureSync(
        online: true,
        jobs: <String, Job>{
          'job-done': _job(
            id: 'job-done',
            number: 105,
            assignedEmployeeId: 'emp-me',
            status: JobStatus.completed,
            startedAt: DateTime.utc(2026, 10, 6, 9, 30),
          ),
        },
      );
      await sl<ConnectivityService>().start();

      await sl<JobsRepository>().saveWorkDescription(
        jobId: 'job-done',
        workDescription: 'Too late.',
      );
      await sl<SyncProcessor>().processPendingOperations();
      await _untilQueueDrained();

      expect(remote.saveCalls, 1);
      expect(remote.events, isEmpty);
      expect(remote.jobById('job-done').workDescription, isNull);
      expect(await sl<SyncQueue>().failedCount(), 1);
    },
  );

  test(
    'client-side validation rejects empty/too-long before anything is queued',
    () async {
      final _ServerLikeJobsRemote remote = await configureSync(
        online: true,
        jobs: inProgressJob(),
      );
      await sl<ConnectivityService>().start();

      await expectLater(
        () => sl<JobsRepository>().saveWorkDescription(
          jobId: 'job-mine',
          workDescription: '   \n  ',
        ),
        throwsArgumentError,
      );
      await expectLater(
        () => sl<JobsRepository>().saveWorkDescription(
          jobId: 'job-mine',
          workDescription: 'a' * (JobsRepository.maxWorkDescriptionLength + 1),
        ),
        throwsArgumentError,
      );

      // Nothing queued, nothing sent, nothing stored.
      expect(await sl<SyncQueue>().pendingCount(), 0);
      expect(await sl<SyncQueue>().failedCount(), 0);
      expect(remote.saveCalls, 0);
      expect(remote.jobById('job-mine').workDescription, isNull);
    },
  );
}

/// The job-files surface is not under test here — never reached (and would
/// need a Supabase client).
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
