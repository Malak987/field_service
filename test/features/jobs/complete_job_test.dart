import 'dart:async';

import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/network/network_info.dart';
import 'package:field_service/features/jobs/data/datasources/job_files_remote_data_source.dart';
import 'package:field_service/features/jobs/data/datasources/jobs_remote_data_source.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';

/// Server-semantics tests for Complete Job against the REAL repository
/// (`JobsRepositoryImpl` with the shared `NetworkInfo`), with only the
/// remote surfaces faked — the fake mirrors the EXACT rules of
/// `supabase/complete_job_setup.sql`: authentication/role, ownership,
/// `in_progress` requirement, the four server-queried completion
/// conditions, atomic status + server `completed_at` + exactly one
/// `job_completed` event, and idempotent replays.
class _ServerLikeCompleteRemote implements JobsRemoteDataSource {
  _ServerLikeCompleteRemote({
    required Map<String, _RemoteJob> jobs,
    required this.authorizedEmployeeId,
    this.isAdmin = false,
  })
    // ignore: prefer_initializing_formals — private field, public parameter.
    : _jobs = jobs;

  /// The server's own clock — the ONLY source of `completed_at`.
  static final DateTime serverNow = DateTime.utc(2026, 10, 7, 16, 15);

  final Map<String, _RemoteJob> _jobs;

  /// The employee row the signed-in user owns (`auth.uid()` → employee).
  final String? authorizedEmployeeId;

  /// The caller's session is an admin. Admins NEVER complete jobs.
  final bool isAdmin;

  /// Every `complete_job` call the server received, with the EXACT payload
  /// (proves the client never sends identity, timestamps or `has_*` flags).
  final List<Map<String, Object?>> completeCalls = <Map<String, Object?>>[];

  /// The `job_events` rows the server appended.
  final List<Map<String, Object?>> events = <Map<String, Object?>>[];

  /// The server's `jobs` rows (test assertions on atomicity).
  Map<String, _RemoteJob> get jobs => _jobs;

  void _assertAuthorized(_RemoteJob job) {
    if (isAdmin) {
      throw StateError('Only the assigned technician can complete a job.');
    }
    if (job.assignedEmployeeId != authorizedEmployeeId) {
      throw StateError('This job is not assigned to you.');
    }
  }

  @override
  Future<Job> completeJob(String jobId) async {
    // The RPC accepts ONLY the job id — recorded so tests can prove that
    // no identity/timestamp/flag travels with the request.
    completeCalls.add(<String, Object?>{'p_job_id': jobId});

    final _RemoteJob? job = _jobs[jobId];
    if (job == null) {
      throw StateError('Job not found.');
    }
    _assertAuthorized(job);

    // Idempotent replay: already completed → return unchanged. No second
    // mutation, no duplicate event, completed_at never reset.
    if (job.status == JobStatus.completed) {
      return job.toDomain();
    }
    if (job.status != JobStatus.inProgress) {
      throw StateError('Job cannot be completed from status "${job.status}".');
    }

    // Completion conditions — the server queries them itself.
    if (!job.fileTypes.contains('before')) {
      throw StateError('A before photo is required to complete this job.');
    }
    if (job.workDescription.trim().isEmpty) {
      throw StateError('A work description is required to complete this job.');
    }
    if (!job.fileTypes.contains('after')) {
      throw StateError('An after photo is required to complete this job.');
    }
    if (!job.fileTypes.contains('signature')) {
      throw StateError(
        'A customer signature is required to complete this job.',
      );
    }

    // Atomic transition: status + SERVER timestamps + exactly one event.
    final _RemoteJob completed = _RemoteJob(
      assignedEmployeeId: job.assignedEmployeeId,
      status: JobStatus.completed,
      workDescription: job.workDescription,
      fileTypes: job.fileTypes,
      completedAt: serverNow,
    );
    _jobs[jobId] = completed;
    events.add(<String, Object?>{
      'job_id': jobId,
      'employee_id': authorizedEmployeeId,
      'event_type': 'job_completed',
      'occurred_at': serverNow,
    });
    return completed.toDomain(jobId: jobId);
  }

  // --- Everything below is not under test here. -----------------------------

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
  Future<Job> startJob(String jobId) async => throw UnimplementedError();
}

/// The server-side job row (minimal — only what completion inspects).
class _RemoteJob {
  const _RemoteJob({
    required this.assignedEmployeeId,
    required this.status,
    this.workDescription = '',
    this.fileTypes = const <String>{},
    this.completedAt,
  });

  final String? assignedEmployeeId;
  final String status;
  final String workDescription;

  /// File types registered in `job_files` for this job.
  final Set<String> fileTypes;
  final DateTime? completedAt;

  Job toDomain({String jobId = 'job-mine'}) {
    return Job(
      id: jobId,
      jobNumber: 101,
      customerId: 'cust-$jobId',
      assignedEmployeeId: assignedEmployeeId,
      jobType: 'kitchen_renovation',
      workDescription: workDescription.isEmpty ? null : workDescription,
      status: JobStatus(status),
      startedAt: DateTime.utc(2026, 10, 6, 9, 30),
      completedAt: completedAt,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
      expiresAt: DateTime.utc(2026, 12, 1),
    );
  }
}

/// The jobs RPC surface is not under test here.
class _UnusedFilesRemote implements JobFilesRemoteDataSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late AppTestHarness app;

  setUp(() => app = AppTestHarness());
  tearDown(() => app.dispose());

  /// Boots the REAL repository stack on [harness] and swaps only the
  /// remote surfaces.
  Future<_ServerLikeCompleteRemote> configureOn(
    AppTestHarness harness, {
    required Map<String, _RemoteJob> jobs,
    String? authorizedEmployeeId = 'emp-me',
    bool isAdmin = false,
    bool online = true,
  }) async {
    await harness.configure(
      user: technicianUser,
      withJobsSync: true,
      jobsOnline: online,
    );

    await sl.unregister<JobsRemoteDataSource>();
    final _ServerLikeCompleteRemote remote = _ServerLikeCompleteRemote(
      jobs: jobs,
      authorizedEmployeeId: authorizedEmployeeId,
      isAdmin: isAdmin,
    );
    sl.registerSingleton<JobsRemoteDataSource>(remote);

    await sl.unregister<JobFilesRemoteDataSource>();
    sl.registerSingleton<JobFilesRemoteDataSource>(_UnusedFilesRemote());

    return remote;
  }

  /// Variant of [configureOn] bound to the shared [app] harness.
  Future<_ServerLikeCompleteRemote> configureCompletion({
    required Map<String, _RemoteJob> jobs,
    String? authorizedEmployeeId = 'emp-me',
    bool isAdmin = false,
    bool online = true,
  }) {
    return configureOn(
      app,
      jobs: jobs,
      authorizedEmployeeId: authorizedEmployeeId,
      isAdmin: isAdmin,
      online: online,
    );
  }

  /// A job where EVERY completion condition is satisfied server-side.
  _RemoteJob completeableJob() {
    return const _RemoteJob(
      assignedEmployeeId: 'emp-me',
      status: JobStatus.inProgress,
      workDescription: 'Replaced the sink and sealed the counter.',
      fileTypes: <String>{'before', 'after', 'signature'},
    );
  }

  test('assigned technician with all requirements completes the job: status, '
      'server completed_at, ONE job_completed event', () async {
    final _ServerLikeCompleteRemote remote = await configureCompletion(
      jobs: <String, _RemoteJob>{'job-mine': completeableJob()},
    );

    final Job completed = await sl<JobsRepository>().completeJob('job-mine');

    // The client sent ONLY the job id — no identity, no timestamp, no
    // has_* flags. The server is the sole authority.
    expect(remote.completeCalls, <Map<String, Object?>>[
      <String, Object?>{'p_job_id': 'job-mine'},
    ]);

    expect(completed.status.value, JobStatus.completed);
    // `completed_at` is the SERVER's timestamp — never a client value.
    expect(completed.completedAt, _ServerLikeCompleteRemote.serverNow);

    // Exactly one event, stamped with the server time.
    expect(remote.events, hasLength(1));
    expect(remote.events.single['event_type'], 'job_completed');
    expect(remote.events.single['job_id'], 'job-mine');
    expect(remote.events.single['employee_id'], 'emp-me');
    expect(
      remote.events.single['occurred_at'],
      _ServerLikeCompleteRemote.serverNow,
    );
  });

  test('a different technician\'s job is refused atomically', () async {
    final _ServerLikeCompleteRemote remote = await configureCompletion(
      jobs: <String, _RemoteJob>{
        'job-other': const _RemoteJob(
          assignedEmployeeId: 'emp-somebody-else',
          status: JobStatus.inProgress,
          workDescription: 'Done.',
          fileTypes: <String>{'before', 'after', 'signature'},
        ),
      },
    );

    await expectLater(
      () => sl<JobsRepository>().completeJob('job-other'),
      throwsStateError,
    );

    // Atomic refusal: no status change, no completed_at, no event.
    expect(remote.jobs['job-other']!.status, JobStatus.inProgress);
    expect(remote.jobs['job-other']!.completedAt, isNull);
    expect(remote.events, isEmpty);
  });

  test('an admin is refused — completion is technician-only', () async {
    final _ServerLikeCompleteRemote remote = await configureCompletion(
      jobs: <String, _RemoteJob>{'job-tech': completeableJob()},
      authorizedEmployeeId: 'emp-admin',
      isAdmin: true,
    );

    await expectLater(
      () => sl<JobsRepository>().completeJob('job-tech'),
      throwsStateError,
    );

    expect(remote.jobs['job-tech']!.status, JobStatus.inProgress);
    expect(remote.events, isEmpty);
  });

  test('a job that is not in_progress is refused', () async {
    final _ServerLikeCompleteRemote remote = await configureCompletion(
      jobs: <String, _RemoteJob>{
        'job-mine': const _RemoteJob(
          assignedEmployeeId: 'emp-me',
          status: JobStatus.assigned,
          workDescription: 'Done.',
          fileTypes: <String>{'before', 'after', 'signature'},
        ),
      },
    );

    await expectLater(
      () => sl<JobsRepository>().completeJob('job-mine'),
      throwsStateError,
    );

    expect(remote.jobs['job-mine']!.status, JobStatus.assigned);
    expect(remote.jobs['job-mine']!.completedAt, isNull);
    expect(remote.events, isEmpty);
  });

  test('missing before photo is refused', () async {
    final _ServerLikeCompleteRemote remote = await configureCompletion(
      jobs: <String, _RemoteJob>{
        'job-mine': const _RemoteJob(
          assignedEmployeeId: 'emp-me',
          status: JobStatus.inProgress,
          workDescription: 'Done.',
          fileTypes: <String>{'after', 'signature'},
        ),
      },
    );

    await expectLater(
      () => sl<JobsRepository>().completeJob('job-mine'),
      throwsStateError,
    );
    expect(remote.jobs['job-mine']!.status, JobStatus.inProgress);
    expect(remote.events, isEmpty); // atomic: nothing changed
  });

  test(
    'missing work description is refused (null and whitespace-only)',
    () async {
      for (final String description in <String>['', '   \t  ']) {
        // A fresh harness per case: DI registrations cannot be rebuilt on an
        // already-configured container.
        final AppTestHarness loopApp = AppTestHarness();
        try {
          final _ServerLikeCompleteRemote remote = await configureOn(
            loopApp,
            jobs: <String, _RemoteJob>{
              'job-mine': _RemoteJob(
                assignedEmployeeId: 'emp-me',
                status: JobStatus.inProgress,
                workDescription: description,
                fileTypes: const <String>{'before', 'after', 'signature'},
              ),
            },
          );

          await expectLater(
            () => sl<JobsRepository>().completeJob('job-mine'),
            throwsStateError,
            reason: 'work description "$description" must be refused',
          );
          expect(remote.jobs['job-mine']!.status, JobStatus.inProgress);
          expect(remote.events, isEmpty);
        } finally {
          await loopApp.dispose();
        }
      }
    },
  );

  test('missing after photo is refused', () async {
    final _ServerLikeCompleteRemote remote = await configureCompletion(
      jobs: <String, _RemoteJob>{
        'job-mine': const _RemoteJob(
          assignedEmployeeId: 'emp-me',
          status: JobStatus.inProgress,
          workDescription: 'Done.',
          fileTypes: <String>{'before', 'signature'},
        ),
      },
    );

    await expectLater(
      () => sl<JobsRepository>().completeJob('job-mine'),
      throwsStateError,
    );
    expect(remote.jobs['job-mine']!.status, JobStatus.inProgress);
    expect(remote.events, isEmpty);
  });

  test('missing customer signature is refused', () async {
    final _ServerLikeCompleteRemote remote = await configureCompletion(
      jobs: <String, _RemoteJob>{
        'job-mine': const _RemoteJob(
          assignedEmployeeId: 'emp-me',
          status: JobStatus.inProgress,
          workDescription: 'Done.',
          fileTypes: <String>{'before', 'after'},
        ),
      },
    );

    await expectLater(
      () => sl<JobsRepository>().completeJob('job-mine'),
      throwsStateError,
    );
    expect(remote.jobs['job-mine']!.status, JobStatus.inProgress);
    expect(remote.events, isEmpty);
  });

  test('replayed completion stays idempotent: no second mutation, no duplicate '
      'event, completed_at untouched', () async {
    final _ServerLikeCompleteRemote remote = await configureCompletion(
      jobs: <String, _RemoteJob>{'job-mine': completeableJob()},
    );

    final JobsRepository repository = sl<JobsRepository>();
    final Job first = await repository.completeJob('job-mine');
    final Job second = await repository.completeJob('job-mine');
    final Job third = await repository.completeJob('job-mine');

    // Every call succeeds (retries are safe)…
    expect(first.status.value, JobStatus.completed);
    expect(second.status.value, JobStatus.completed);
    expect(third.status.value, JobStatus.completed);

    // …but the transition happened exactly once.
    expect(remote.events, hasLength(1));
    expect(second.completedAt, first.completedAt);
    expect(third.completedAt, first.completedAt);
    expect(
      remote.completeCalls,
      hasLength(3), // three requests, ONE effect
    );
  });

  test('offline completion is refused BEFORE the network — the job stays '
      'in_progress and no local event is invented', () async {
    final _ServerLikeCompleteRemote remote = await configureCompletion(
      jobs: <String, _RemoteJob>{'job-mine': completeableJob()},
      online: true, // swapped below, AFTER the repository graph resolves
    );

    // No connectivity — completion must fail fast and authoritatively.
    await sl.unregister<NetworkInfo>();
    sl.registerSingleton<NetworkInfo>(_OfflineNetworkInfo());

    await expectLater(
      () => sl<JobsRepository>().completeJob('job-mine'),
      throwsA(isA<JobCompletionOfflineException>()),
    );

    // Nothing reached the server, nothing was invented locally: no
    // status change, no completed_at, no `job_completed` event.
    expect(remote.completeCalls, isEmpty);
    expect(remote.jobs['job-mine']!.status, JobStatus.inProgress);
    expect(remote.jobs['job-mine']!.completedAt, isNull);
    expect(remote.events, isEmpty);
  });
}

/// Offline connectivity (same shape as the harness's own fakes).
class _OfflineNetworkInfo implements NetworkInfo {
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  @override
  Future<bool> get isConnected async => false;

  @override
  Stream<bool> get onConnectionChanged => _controller.stream;
}
