import 'dart:async';

import 'package:drift/native.dart';
import 'package:field_service/app/app.dart';
import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_router.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/database/app_database.dart';
import 'package:field_service/core/network/connectivity_service.dart';
import 'package:field_service/core/network/network_info.dart';
import 'package:field_service/core/sync/sync_manager.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/domain/repositories/authentication_repository.dart';
import 'package:field_service/features/customers/data/datasources/customers_remote_data_source.dart';
import 'package:field_service/features/customers/data/models/customer_model.dart';
import 'package:field_service/features/employees/domain/entities/employee.dart';
import 'package:field_service/features/employees/domain/repositories/employees_repository.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

import 'dart:typed_data';

import 'test_photos.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_authentication_repository.dart';

/// Uses the production DI graph, routes, cubits, customer repository, Drift
/// tables and durable sync queue. Only the external auth/network is replaced.
///
/// Jobs behaviour has two modes:
/// * default — a fake [JobsRepository] that mirrors RLS visibility (see
///   [_FakeJobsRepository]); used by UI/navigation tests;
/// * `withJobsSync: true` — the REAL `JobsRepositoryImpl` + durable Drift
///   `SyncQueue` + shared `SyncManager`, with only the remote data source
///   faked; used by the Start Job offline/sync tests.
class AppTestHarness {
  final TestAuthenticationRepository authentication =
      TestAuthenticationRepository();
  late GoRouter router;
  AppDatabase? database;
  _FakeJobsRepository? _fakeJobs;

  /// Whether [configure] ran — plain (non-widget) tests may use the harness
  /// type without booting the app; [dispose] must not crash for them.
  bool _configured = false;

  /// Job ids the fake "server" accepted a start for (UI test assertions).
  /// Empty when running with the real sync-mode repository.
  List<String> get startedJobIds =>
      _fakeJobs?.startedJobIds ?? const <String>[];

  /// The Create & Assign requests the fake "server" accepted, in order
  /// (payload: customer id, category, description, assigned technician).
  List<Map<String, Object?>> get createJobCalls =>
      _fakeJobs?.createJobCalls ?? const <Map<String, Object?>>[];

  /// Jobs the fake "server" created through the `create_job` RPC.
  List<Job> get createdJobs => _fakeJobs?.createdJobs ?? const <Job>[];

  /// The work descriptions the fake "server" accepted, by job id (in order).
  Map<String, List<String>> get savedWorkDescriptions =>
      _fakeJobs?.savedWorkDescriptions ?? const <String, List<String>>{};

  Future<void> configure({
    AppUser? user,
    String initialLocation = AppRoutes.root,
    bool withCustomers = false,
    List<Job> jobs = const <Job>[],
    Map<String, JobCustomerInfo?> jobCustomers =
        const <String, JobCustomerInfo?>{},
    List<Employee> technicians = const <Employee>[],
    Object? techniciansError,
    bool jobsOffline = false,
    Object? startJobError,
    Object? createJobError,
    Object? saveWorkDescriptionError,
    Set<String> alreadyStartedJobIds = const <String>{},
    bool withJobsSync = false,
    bool jobsOnline = false,
    Set<String> photoDeniedJobIds = const <String>{},
    Map<String, List<JobFile>> initialBeforePhotos =
        const <String, List<JobFile>>{},
    Map<String, List<JobFile>> initialAfterPhotos =
        const <String, List<JobFile>>{},
    Map<String, List<JobFile>> initialSignatures =
        const <String, List<JobFile>>{},
    bool completionOffline = false,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await configureDependencies();
    authentication.currentUser = user;
    await sl.unregister<AuthenticationRepository>();
    sl.registerSingleton<AuthenticationRepository>(authentication);

    if (!withJobsSync) {
      _fakeJobs = _FakeJobsRepository(
        jobs: jobs,
        jobCustomers: jobCustomers,
        offline: jobsOffline,
        startJobError: startJobError,
        createJobError: createJobError,
        saveWorkDescriptionError: saveWorkDescriptionError,
        alreadyStartedJobIds: alreadyStartedJobIds,
        photoDeniedJobIds: photoDeniedJobIds,
        initialBeforePhotos: initialBeforePhotos,
        initialAfterPhotos: initialAfterPhotos,
        initialSignatures: initialSignatures,
        isAdminUser: user != null && !user.isTechnician,
        completionOffline: completionOffline,
      );
      await sl.unregister<JobsRepository>();
      sl.registerSingleton<JobsRepository>(_fakeJobs!);
    }

    // Employees read (assignee options of the admin Create Job screen).
    await sl.unregister<EmployeesRepository>();
    sl.registerSingleton<EmployeesRepository>(
      _FakeEmployeesRepository(
        technicians: technicians,
        error: techniciansError,
      ),
    );

    if (withCustomers || withJobsSync) {
      database = AppDatabase(NativeDatabase.memory());
      await sl.unregister<AppDatabase>();
      sl.registerSingleton<AppDatabase>(database!, dispose: (db) => db.close());
      await sl.unregister<NetworkInfo>();
      sl.registerSingleton<NetworkInfo>(
        jobsOnline ? _OnlineNetworkInfo() : _OfflineNetworkInfo(),
      );
    }

    if (withCustomers) {
      await sl.unregister<CustomersRemoteDataSource>();
      sl.registerSingleton<CustomersRemoteDataSource>(
        _UnusedCustomersRemoteDataSource(),
      );
    }

    router = AppRouter(initialLocation: initialLocation).router;
    _configured = true;
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(FieldServiceApp(router: router));
    await tester.pumpAndSettle();
  }

  // --- Before Photos (fake-server facts, UI-test assertions) ------------------

  /// The before photos the fake server has registered, by job id.
  Map<String, List<JobFile>> get serverBeforePhotos =>
      _fakeJobs?.photos ?? const <String, List<JobFile>>{};

  /// Job ids the fake server accepted a before photo for.
  List<String> get photoAddedJobIds =>
      _fakeJobs?.photoAddedJobIds ?? const <String>[];

  /// Capture timestamps the fake server recorded (automatic, never manual).
  List<DateTime> get photoCapturedAt =>
      _fakeJobs?.photoCapturedAt ?? const <DateTime>[];

  // --- After Photos (fake-server facts, UI-test assertions) -------------------

  /// The after photos the fake server has registered, by job id.
  Map<String, List<JobFile>> get serverAfterPhotos =>
      _fakeJobs?.afterPhotos ?? const <String, List<JobFile>>{};

  /// Job ids the fake server accepted an after photo for.
  List<String> get afterPhotoAddedJobIds =>
      _fakeJobs?.afterPhotoAddedJobIds ?? const <String>[];

  /// After-photo capture timestamps the fake server recorded (automatic).
  List<DateTime> get afterPhotoCapturedAt =>
      _fakeJobs?.afterPhotoCapturedAt ?? const <DateTime>[];

  // --- Customer Signature (fake-server facts, UI-test assertions) -------------

  /// The signature files the fake server has registered, by job id.
  Map<String, List<JobFile>> get serverSignatures =>
      _fakeJobs?.signatures ?? const <String, List<JobFile>>{};

  /// Job ids the fake server accepted a signature capture for.
  List<String> get signatureCapturedJobIds =>
      _fakeJobs?.signatureCapturedJobIds ?? const <String>[];

  /// Signature capture timestamps the fake server recorded (automatic).
  List<DateTime> get signatureCapturedAt =>
      _fakeJobs?.signatureCapturedAt ?? const <DateTime>[];

  // --- Complete Job (fake-server facts, UI-test assertions) -------------------

  /// Job ids the fake server accepted a completion for, in order.
  List<String> get completedJobIds =>
      _fakeJobs?.completedJobIds ?? const <String>[];

  /// The `job_completed` events the fake server appended (exactly one per
  /// accepted completion — never per retry).
  List<Map<String, Object?>> get jobCompletedEvents =>
      _fakeJobs?.jobCompletedEvents ?? const <Map<String, Object?>>[];

  /// The PNG bytes the fake server accepted, by job id (wire assertions).
  Map<String, List<Uint8List>> get signatureImages =>
      _fakeJobs?.signatureImages ?? const <String, List<Uint8List>>{};

  /// How often the Retry action reached the fake sync engine.
  int get photoRetryCalls => _fakeJobs?.retryCalls ?? 0;

  /// Marks the given photo ids as having a `failed` upload in the queue
  /// (drives the "Upload failed" badge + Retry in the UI).
  set failedPhotoIds(Set<String> ids) {
    _fakeJobs?.failedPhotoIds = ids;
  }

  Future<void> dispose() async {
    if (!_configured) {
      await authentication.dispose();
      return;
    }
    router.dispose();
    _fakeJobs?.dispose();
    if (database != null) {
      await sl<SyncManager>().dispose();
      await sl<ConnectivityService>().dispose();
    }
    await resetDependencies();
    await authentication.dispose();
  }
}

/// Test double for the Employees read: serves exactly the technicians the
/// test configured (mirrors the RLS-scoped `employees` select). An optional
/// [error] simulates a refused/failed lookup.
class _FakeEmployeesRepository implements EmployeesRepository {
  _FakeEmployeesRepository({required this.technicians, this.error});

  final List<Employee> technicians;
  final Object? error;

  @override
  Future<List<Employee>> getActiveTechnicians() async {
    if (error != null) {
      throw error!; // ignore: only_throw_errors
    }
    return technicians;
  }
}

class _OfflineNetworkInfo implements NetworkInfo {
  @override
  Future<bool> get isConnected async => false;

  @override
  Stream<bool> get onConnectionChanged => Stream<bool>.value(false);
}

class _OnlineNetworkInfo implements NetworkInfo {
  @override
  Future<bool> get isConnected async => true;

  @override
  Stream<bool> get onConnectionChanged => Stream<bool>.value(true);
}

class _UnusedCustomersRemoteDataSource implements CustomersRemoteDataSource {
  @override
  Future<List<CustomerModel>> fetchAll() async => <CustomerModel>[];

  @override
  Future<void> upsertRow(Map<String, Object?> row) async =>
      throw StateError('Offline UI tests must not push customer writes.');

  @override
  Future<bool> updateRow({
    required String id,
    required Map<String, Object?> changes,
  }) async =>
      throw StateError('Offline UI tests must not push customer writes.');

  @override
  Future<bool> deleteRow(String id) async =>
      throw StateError('Offline UI tests must not push customer writes.');
}

/// The authoritative `started_at` the fake "server" stamps when it accepts a
/// start — proves the UI never invents a client timestamp.
final DateTime serverStartedAt = DateTime.utc(2026, 10, 6, 9, 30);

/// The authoritative `completed_at` the fake "server" stamps when it accepts
/// a completion — proves the UI never invents a client timestamp.
final DateTime serverCompletedAt = DateTime.utc(2026, 10, 7, 16, 15);

/// Test double for the Jobs feature.
///
/// It mirrors the server-side facts the UI relies on:
/// * [jobs] is exactly the set the caller may see (RLS on `public.jobs`),
///   so [getJobById] throws for any id outside of it — precisely what an
///   RLS-filtered `maybeSingle()` produces for a job that belongs to
///   somebody else (or does not exist).
/// * [jobCustomers] mirrors the `get_job_customer` RPC: customer info is
///   keyed by **job id**, never by customer id, and is only served for jobs
///   in [jobs] (the RPC refuses everything else with zero rows).
/// * [startJob] mirrors the `start_job` RPC: it applies `in_progress` plus
///   the SERVER-generated [serverStartedAt] (never a client value), refuses
///   jobs listed in [alreadyStartedJobIds] with
///   [JobAlreadyStartedException], and any other configured failure via
///   [startJobError] (e.g. "not assigned to you" for another technician's
///   or an unassigned job).
///
/// With [offline] set, every read fails like a network outage would.
class _FakeJobsRepository implements JobsRepository {
  _FakeJobsRepository({
    required List<Job> jobs,
    required this.jobCustomers,
    required this.offline,
    this.startJobError,
    this.createJobError,
    this.saveWorkDescriptionError,
    this.alreadyStartedJobIds = const <String>{},
    Set<String> photoDeniedJobIds = const <String>{},
    Map<String, List<JobFile>> initialBeforePhotos =
        const <String, List<JobFile>>{},
    Map<String, List<JobFile>> initialAfterPhotos =
        const <String, List<JobFile>>{},
    Map<String, List<JobFile>> initialSignatures =
        const <String, List<JobFile>>{},
    this.isAdminUser = false,
    this.completionOffline = false,
  }) : jobs = List<Job>.of(jobs),
       photoDeniedJobIds = Set<String>.of(photoDeniedJobIds),
       photos = <String, List<JobFile>>{
         for (final MapEntry<String, List<JobFile>> e
             in initialBeforePhotos.entries)
           e.key: List<JobFile>.of(e.value),
       },
       afterPhotos = <String, List<JobFile>>{
         for (final MapEntry<String, List<JobFile>> e
             in initialAfterPhotos.entries)
           e.key: List<JobFile>.of(e.value),
       },
       signatures = <String, List<JobFile>>{
         for (final MapEntry<String, List<JobFile>> e
             in initialSignatures.entries)
           e.key: List<JobFile>.of(e.value),
       };

  final List<Job> jobs;
  final Map<String, JobCustomerInfo?> jobCustomers;
  final bool offline;

  /// The configured user is an admin — mirrors the RPC's rule that admins
  /// never execute technician workflow actions (refused even directly).
  final bool isAdminUser;

  /// Complete Job specifically has no connectivity (the REAL repository
  /// checks `NetworkInfo` before the RPC) — independent of [offline] so the
  /// checklist streams can still feed the UI.
  final bool completionOffline;
  final Object? startJobError;
  final Object? createJobError;
  final Object? saveWorkDescriptionError;
  final Set<String> alreadyStartedJobIds;

  /// Job ids the fake server accepted a start for (test assertions).
  final List<String> startedJobIds = <String>[];

  /// Create & Assign requests the fake server accepted (assertions).
  final List<Map<String, Object?>> createJobCalls = <Map<String, Object?>>[];

  /// Jobs the fake server created (mirrors the `create_job` RPC result).
  final List<Job> createdJobs = <Job>[];

  /// Work descriptions the fake server accepted, by job id (mirrors the
  /// `save_work_description` RPC effect).
  final Map<String, List<String>> savedWorkDescriptions =
      <String, List<String>>{};

  /// Job ids the fake server accepted a completion for (mirrors the
  /// `complete_job` RPC effect; one entry per accepted completion).
  final List<String> completedJobIds = <String>[];

  /// The `job_completed` events the fake server appended (asserts the
  /// exactly-one-event rule across retries).
  final List<Map<String, Object?>> jobCompletedEvents =
      <Map<String, Object?>>[];

  // --- Before Photos (mirrors the `register_job_file` RPC semantics) ----------

  /// Registered before photos by job id (the fake server's `job_files`).
  final Map<String, List<JobFile>> photos;

  /// Jobs the fake RPC refuses with an authorization error — mirrors
  /// `This job is not assigned to you.` (another technician's job,
  /// unassigned job, …). Server-side enforcement; the UI cannot bypass it.
  final Set<String> photoDeniedJobIds;

  /// Job ids the fake server accepted a before photo for.
  final List<String> photoAddedJobIds = <String>[];

  /// Automatic capture timestamps recorded by the fake server.
  final List<DateTime> photoCapturedAt = <DateTime>[];

  // --- After Photos (same `register_job_file` RPC semantics, type 'after') ---

  /// Registered after photos by job id (the fake server's `job_files`).
  final Map<String, List<JobFile>> afterPhotos;

  /// Job ids the fake server accepted an after photo for.
  final List<String> afterPhotoAddedJobIds = <String>[];

  /// Automatic after-photo capture timestamps recorded by the fake server.
  final List<DateTime> afterPhotoCapturedAt = <DateTime>[];

  // --- Customer Signature (same RPC semantics, type 'signature') -------------

  /// Registered signature files by job id (the fake server's `job_files`).
  final Map<String, List<JobFile>> signatures;

  /// Job ids the fake server accepted a signature capture for.
  final List<String> signatureCapturedJobIds = <String>[];

  /// Automatic signature capture timestamps recorded by the fake server.
  final List<DateTime> signatureCapturedAt = <DateTime>[];

  /// The PNG bytes the fake server accepted, by job id.
  final Map<String, List<Uint8List>> signatureImages =
      <String, List<Uint8List>>{};

  /// Photo ids whose queued upload sits in the `failed` sync state.
  Set<String> failedPhotoIds = <String>{};

  /// Retry-action counter.
  int retryCalls = 0;

  int _photoCounter = 0;
  final Map<String, StreamController<List<JobFile>>> _photoWatchers =
      <String, StreamController<List<JobFile>>>{};
  final Map<String, StreamController<List<JobFile>>> _afterPhotoWatchers =
      <String, StreamController<List<JobFile>>>{};
  final Map<String, StreamController<List<JobFile>>> _signatureWatchers =
      <String, StreamController<List<JobFile>>>{};

  void dispose() {
    for (final StreamController<List<JobFile>> c in _photoWatchers.values) {
      c.close();
    }
    _photoWatchers.clear();
    for (final StreamController<List<JobFile>> c
        in _afterPhotoWatchers.values) {
      c.close();
    }
    _afterPhotoWatchers.clear();
    for (final StreamController<List<JobFile>> c in _signatureWatchers.values) {
      c.close();
    }
    _signatureWatchers.clear();
  }

  void _emitPhotos(String jobId) {
    final StreamController<List<JobFile>>? controller = _photoWatchers[jobId];
    if (controller != null && !controller.isClosed) {
      controller.add(List<JobFile>.of(photos[jobId] ?? const <JobFile>[]));
    }
  }

  void _emitAfterPhotos(String jobId) {
    final StreamController<List<JobFile>>? controller =
        _afterPhotoWatchers[jobId];
    if (controller != null && !controller.isClosed) {
      controller.add(List<JobFile>.of(afterPhotos[jobId] ?? const <JobFile>[]));
    }
  }

  void _emitSignatures(String jobId) {
    final StreamController<List<JobFile>>? controller =
        _signatureWatchers[jobId];
    if (controller != null && !controller.isClosed) {
      controller.add(List<JobFile>.of(signatures[jobId] ?? const <JobFile>[]));
    }
  }

  @override
  Future<List<Job>> getJobs() async {
    if (offline) {
      throw StateError('Simulated network outage.');
    }
    return jobs;
  }

  @override
  Future<Job> getJobById(String id) async {
    if (offline) {
      throw StateError('Simulated network outage.');
    }
    final Job? job = jobs.where((Job j) => j.id == id).firstOrNull;
    if (job == null) {
      // Same shape as the real data source when RLS hides the row.
      throw StateError('Job not found: $id');
    }
    return job;
  }

  @override
  Future<JobCustomerInfo?> getJobCustomerInfo(String jobId) async {
    if (offline) {
      throw StateError('Simulated network outage.');
    }
    final bool visible = jobs.any((Job j) => j.id == jobId);
    if (!visible) {
      // The RPC returns zero rows for jobs the caller is not entitled to.
      return null;
    }
    return jobCustomers[jobId];
  }

  @override
  Future<void> startJob(String jobId) async {
    if (offline) {
      throw StateError('Simulated network outage.');
    }
    if (alreadyStartedJobIds.contains(jobId)) {
      throw JobAlreadyStartedException(jobId);
    }
    if (startJobError != null) {
      throw startJobError!; // ignore: only_throw_errors
    }

    startedJobIds.add(jobId);
    // The "server" applies the start: status + its OWN timestamp. The local
    // mirror is updated too, so a following [getJobById] returns the
    // authoritative row (what a refresh after the push resolves shows).
    for (int i = 0; i < jobs.length; i++) {
      if (jobs[i].id == jobId) {
        jobs[i] = jobs[i].copyWith(
          status: const JobStatus(JobStatus.inProgress),
          startedAt: serverStartedAt,
          updatedAt: serverStartedAt,
        );
      }
    }
  }

  @override
  Future<Job> createJob({
    required String customerId,
    required String jobType,
    String? description,
    required String assignedEmployeeId,
  }) async {
    if (offline) {
      throw StateError('Simulated network outage.');
    }
    if (createJobError != null) {
      throw createJobError!; // ignore: only_throw_errors
    }
    // Mirrors the `create_job` RPC: only the two supported categories,
    // `status = 'assigned'` and a SERVER `assigned_at` — the client never
    // contributes a timestamp. The job number is generated HERE, on the
    // fake server (next free number, modeling the real identity column —
    // the client never sends one and receives the generated value back).
    if (!JobCategory.isSupported(jobType)) {
      throw StateError('Unsupported job category: $jobType');
    }

    final int nextNumber =
        jobs.fold<int>(
          0,
          (int max, Job job) => job.jobNumber > max ? job.jobNumber : max,
        ) +
        1;

    final Job created = Job(
      id: 'fake-created-$nextNumber',
      jobNumber: nextNumber,
      customerId: customerId,
      assignedEmployeeId: assignedEmployeeId,
      jobType: jobType,
      description: description,
      status: const JobStatus(JobStatus.assigned),
      assignedAt: serverStartedAt,
      createdAt: serverStartedAt,
      updatedAt: serverStartedAt,
      expiresAt: serverStartedAt.add(const Duration(days: 90)),
    );

    jobs.insert(0, created);
    createdJobs.add(created);
    createJobCalls.add(<String, Object?>{
      'customer_id': customerId,
      'job_type': jobType,
      'description': description,
      'assigned_employee_id': assignedEmployeeId,
    });
    return created;
  }

  @override
  Future<void> saveWorkDescription({
    required String jobId,
    required String workDescription,
  }) async {
    if (offline) {
      throw StateError('Simulated network outage.');
    }
    if (saveWorkDescriptionError != null) {
      throw saveWorkDescriptionError!; // ignore: only_throw_errors
    }
    // Mirrors the `save_work_description` RPC (UI-test facts): the text is
    // trimmed, must not be empty, and only exists for visible jobs. The
    // server-side timestamp lives in the event — the client sends none.
    final String clean = workDescription.trim();
    if (clean.isEmpty) {
      throw StateError('Work description cannot be empty.');
    }
    for (int i = 0; i < jobs.length; i++) {
      if (jobs[i].id == jobId) {
        jobs[i] = jobs[i].copyWith(
          workDescription: clean,
          updatedAt: serverStartedAt,
        );
        savedWorkDescriptions.putIfAbsent(jobId, () => <String>[]).add(clean);
        return;
      }
    }
    // RLS mirror: a job outside the caller's visibility is unknown.
    throw StateError('Job not found: $jobId');
  }

  @override
  Future<void> updateJobStatus({
    required String jobId,
    required String status,
  }) async => throw UnimplementedError();

  // --- Before Photos ---------------------------------------------------------

  @override
  Future<String> addBeforePhoto({
    required String jobId,
    required String pickedFilePath,
  }) async {
    if (offline) {
      throw StateError('Simulated network outage.');
    }
    final Job? job = jobs.where((Job j) => j.id == jobId).firstOrNull;
    if (job == null) {
      // RLS mirror: a job outside the caller's visibility is unknown.
      throw StateError('Job not found: $jobId');
    }
    if (job.assignedEmployeeId == null || photoDeniedJobIds.contains(jobId)) {
      // Mirrors the RPC's server-side ownership refusal (ERRCODE 42501):
      // unassigned jobs and other technicians' jobs are rejected.
      throw StateError('This job is not assigned to you.');
    }
    if (job.status.value != JobStatus.inProgress) {
      // Mirrors the RPC's business rule: before photos only while started.
      throw StateError(
        'Before photos can only be added to a job that is in progress.',
      );
    }

    final DateTime capturedAt = DateTime.now();
    final JobFile file = JobFile(
      id: 'fake-photo-$jobId-${_photoCounter++}',
      jobId: jobId,
      fileType: 'before',
      fileName: 'before_$_photoCounter.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: kTestPhotoBytes.length,
      capturedAt: capturedAt,
      remotePath: 'jobs/$jobId/before/fake-$_photoCounter.jpg',
      syncState: JobFileSyncState.synced,
    );

    photos[jobId] = <JobFile>[...?photos[jobId], file];
    photoAddedJobIds.add(jobId);
    photoCapturedAt.add(capturedAt);
    _emitPhotos(jobId);
    return file.id;
  }

  @override
  Future<List<JobFile>> getBeforePhotos(String jobId) async {
    if (offline) {
      throw StateError('Simulated network outage.');
    }
    final bool visible = jobs.any((Job j) => j.id == jobId);
    if (!visible) {
      // RLS mirror: zero rows for jobs the caller cannot see.
      return const <JobFile>[];
    }
    return List<JobFile>.of(photos[jobId] ?? const <JobFile>[]);
  }

  @override
  Stream<List<JobFile>> watchBeforePhotos(String jobId) {
    if (offline) {
      return Stream<List<JobFile>>.error(
        StateError('Simulated network outage.'),
      );
    }
    final StreamController<List<JobFile>> controller = _photoWatchers
        .putIfAbsent(jobId, () => StreamController<List<JobFile>>.broadcast());
    scheduleMicrotask(() {
      if (!controller.isClosed) {
        controller.add(List<JobFile>.of(photos[jobId] ?? const <JobFile>[]));
      }
    });
    return controller.stream;
  }

  // --- After Photos ------------------------------------------------------------

  @override
  Future<String> addAfterPhoto({
    required String jobId,
    required String pickedFilePath,
  }) async {
    if (offline) {
      throw StateError('Simulated network outage.');
    }
    final Job? job = jobs.where((Job j) => j.id == jobId).firstOrNull;
    if (job == null) {
      // RLS mirror: a job outside the caller's visibility is unknown.
      throw StateError('Job not found: $jobId');
    }
    if (job.assignedEmployeeId == null || photoDeniedJobIds.contains(jobId)) {
      // Mirrors the RPC's server-side ownership refusal (ERRCODE 42501):
      // unassigned jobs and other technicians' jobs are rejected.
      throw StateError('This job is not assigned to you.');
    }
    if (job.status.value != JobStatus.inProgress) {
      // Mirrors the RPC's business rule: after photos only while started.
      throw StateError(
        'Photos can only be added to a job that is in progress.',
      );
    }

    final DateTime capturedAt = DateTime.now();
    final JobFile file = JobFile(
      id: 'fake-after-photo-$jobId-${_photoCounter++}',
      jobId: jobId,
      fileType: 'after',
      fileName: 'after_$_photoCounter.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: kTestPhotoBytes.length,
      capturedAt: capturedAt,
      remotePath: 'jobs/$jobId/after/fake-$_photoCounter.jpg',
      syncState: JobFileSyncState.synced,
    );

    afterPhotos[jobId] = <JobFile>[...?afterPhotos[jobId], file];
    afterPhotoAddedJobIds.add(jobId);
    afterPhotoCapturedAt.add(capturedAt);
    _emitAfterPhotos(jobId);
    return file.id;
  }

  @override
  Future<List<JobFile>> getAfterPhotos(String jobId) async {
    if (offline) {
      throw StateError('Simulated network outage.');
    }
    final bool visible = jobs.any((Job j) => j.id == jobId);
    if (!visible) {
      // RLS mirror: zero rows for jobs the caller cannot see.
      return const <JobFile>[];
    }
    return List<JobFile>.of(afterPhotos[jobId] ?? const <JobFile>[]);
  }

  @override
  Stream<List<JobFile>> watchAfterPhotos(String jobId) {
    if (offline) {
      return Stream<List<JobFile>>.error(
        StateError('Simulated network outage.'),
      );
    }
    final StreamController<List<JobFile>> controller = _afterPhotoWatchers
        .putIfAbsent(jobId, () => StreamController<List<JobFile>>.broadcast());
    scheduleMicrotask(() {
      if (!controller.isClosed) {
        controller.add(
          List<JobFile>.of(afterPhotos[jobId] ?? const <JobFile>[]),
        );
      }
    });
    return controller.stream;
  }

  @override
  Future<Uint8List?> readPhotoBytes(JobFile file) async {
    return kTestPhotoBytes;
  }

  @override
  Future<Set<String>> failedJobFileIds() async {
    return Set<String>.of(failedPhotoIds);
  }

  @override
  Future<void> retryFailedSyncs() async {
    retryCalls++;
    // Mirrors a successful retry: failed uploads flip to synced.
    failedPhotoIds = <String>{};
    for (final String jobId in photos.keys.toList()) {
      _emitPhotos(jobId);
    }
    for (final String jobId in afterPhotos.keys.toList()) {
      _emitAfterPhotos(jobId);
    }
    for (final String jobId in signatures.keys.toList()) {
      _emitSignatures(jobId);
    }
  }

  // --- Customer Signature ------------------------------------------------------

  @override
  Future<String> captureCustomerSignature({
    required String jobId,
    required Uint8List signatureImage,
  }) async {
    if (offline) {
      throw StateError('Simulated network outage.');
    }
    if (signatureImage.isEmpty) {
      // Mirrors the server-side validation: an empty signature is refused.
      throw ArgumentError.value(
        signatureImage,
        'signatureImage',
        'The signature image is empty',
      );
    }
    final Job? job = jobs.where((Job j) => j.id == jobId).firstOrNull;
    if (job == null) {
      // RLS mirror: a job outside the caller's visibility is unknown.
      throw StateError('Job not found: $jobId');
    }
    if (job.assignedEmployeeId == null || photoDeniedJobIds.contains(jobId)) {
      // Mirrors the RPC's server-side ownership refusal (ERRCODE 42501):
      // unassigned jobs and other technicians' jobs are rejected.
      throw StateError('This job is not assigned to you.');
    }
    if (job.status.value != JobStatus.inProgress) {
      // Mirrors the RPC's business rule: signatures only while started.
      throw StateError(
        'Job files can only be added to a job that is in progress.',
      );
    }

    final DateTime capturedAt = DateTime.now();
    final JobFile file = JobFile(
      id: 'fake-signature-$jobId-${_photoCounter++}',
      jobId: jobId,
      fileType: 'signature',
      fileName: 'signature.png',
      mimeType: 'image/png',
      sizeBytes: signatureImage.length,
      capturedAt: capturedAt,
      remotePath: 'jobs/$jobId/signature/fake-$_photoCounter.png',
      syncState: JobFileSyncState.synced,
    );

    signatures[jobId] = <JobFile>[...?signatures[jobId], file];
    signatureCapturedJobIds.add(jobId);
    signatureCapturedAt.add(capturedAt);
    signatureImages.putIfAbsent(jobId, () => <Uint8List>[]).add(signatureImage);
    _emitSignatures(jobId);
    return file.id;
  }

  @override
  Future<List<JobFile>> getSignatureFiles(String jobId) async {
    if (offline) {
      throw StateError('Simulated network outage.');
    }
    final bool visible = jobs.any((Job j) => j.id == jobId);
    if (!visible) {
      // RLS mirror: zero rows for jobs the caller cannot see.
      return const <JobFile>[];
    }
    return List<JobFile>.of(signatures[jobId] ?? const <JobFile>[]);
  }

  @override
  Stream<List<JobFile>> watchSignatureFiles(String jobId) {
    if (offline) {
      return Stream<List<JobFile>>.error(
        StateError('Simulated network outage.'),
      );
    }
    final StreamController<List<JobFile>> controller = _signatureWatchers
        .putIfAbsent(jobId, () => StreamController<List<JobFile>>.broadcast());
    scheduleMicrotask(() {
      if (!controller.isClosed) {
        controller.add(
          List<JobFile>.of(signatures[jobId] ?? const <JobFile>[]),
        );
      }
    });
    return controller.stream;
  }

  // --- Complete Job (mirrors the `complete_job` RPC semantics) ----------------

  @override
  Future<Job> completeJob(String jobId) async {
    if (offline || completionOffline) {
      // The REAL repository refuses offline before reaching the network
      // (JobCompletionOfflineException); the fake mirrors that contract —
      // completion is authoritative and never faked locally.
      throw const JobCompletionOfflineException();
    }
    final Job? job = jobs.where((Job j) => j.id == jobId).firstOrNull;
    if (job == null) {
      // RLS mirror: a job outside the caller's visibility is unknown.
      throw StateError('Job not found: $jobId');
    }
    if (isAdminUser) {
      // Mirrors the RPC: admins NEVER complete jobs — read-only monitoring.
      throw const JobCompletionRejectedException(
        reason: CompletionRejectReason.unauthorized,
        serverMessage: 'Only the assigned technician can complete a job.',
      );
    }
    if (job.assignedEmployeeId == null || photoDeniedJobIds.contains(jobId)) {
      // Mirrors the RPC's ownership refusal: unassigned jobs and other
      // technicians' jobs are rejected.
      throw const JobCompletionRejectedException(
        reason: CompletionRejectReason.notAssigned,
        serverMessage: 'This job is not assigned to you.',
      );
    }
    if (job.status.value == JobStatus.completed) {
      // Idempotent replay: already completed — return the row UNCHANGED.
      // No second mutation, no duplicate event, completed_at untouched.
      return job;
    }
    if (job.status.value != JobStatus.inProgress) {
      throw const JobCompletionRejectedException(
        reason: CompletionRejectReason.invalidStatus,
        serverMessage: 'Job cannot be completed from this status.',
      );
    }
    // Completion conditions — the "server" queries them itself; no flag
    // from the client is trusted. If any is missing, NOTHING changes.
    //
    // A file only exists SERVER-side once its upload was confirmed — i.e.
    // its local mirror has reached `synced` (exactly what the real
    // `job_files` table reflects). A locally captured but still
    // pending/in-flight/failed file is invisible here, just like on the
    // real backend.
    bool serverHas(List<JobFile> files) {
      return files.any(
        (JobFile file) => file.syncState == JobFileSyncState.synced,
      );
    }

    if (!serverHas(photos[jobId] ?? const <JobFile>[])) {
      throw const JobCompletionRejectedException(
        reason: CompletionRejectReason.missingBeforePhoto,
        serverMessage: 'A before photo is required to complete this job.',
      );
    }
    if ((job.workDescription ?? '').trim().isEmpty) {
      throw const JobCompletionRejectedException(
        reason: CompletionRejectReason.missingWorkDescription,
        serverMessage: 'A work description is required to complete this job.',
      );
    }
    if (!serverHas(afterPhotos[jobId] ?? const <JobFile>[])) {
      throw const JobCompletionRejectedException(
        reason: CompletionRejectReason.missingAfterPhoto,
        serverMessage: 'An after photo is required to complete this job.',
      );
    }
    if (!serverHas(signatures[jobId] ?? const <JobFile>[])) {
      throw const JobCompletionRejectedException(
        reason: CompletionRejectReason.missingSignature,
        serverMessage: 'A customer signature is required to complete this job.',
      );
    }

    // Atomic completion: status + SERVER timestamp (never a client value)
    // + exactly ONE `job_completed` event.
    final Job completed = job.copyWith(
      status: const JobStatus(JobStatus.completed),
      completedAt: serverCompletedAt,
      updatedAt: serverCompletedAt,
    );
    for (int i = 0; i < jobs.length; i++) {
      if (jobs[i].id == jobId) {
        jobs[i] = completed;
      }
    }
    completedJobIds.add(jobId);
    jobCompletedEvents.add(<String, Object?>{
      'job_id': jobId,
      'event_type': 'job_completed',
      'occurred_at': serverCompletedAt,
    });
    return completed;
  }
}
