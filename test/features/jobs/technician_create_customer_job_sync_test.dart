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
import 'package:field_service/features/jobs/data/repositories/jobs_repository_impl.dart';
import 'package:field_service/features/jobs/data/sync/job_sync_handler.dart';
import 'package:field_service/features/jobs/domain/entities/accessible_customer.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/domain/entities/new_customer_draft.dart';
import 'package:field_service/features/jobs/domain/entities/technician_job_creation.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';

/// Offline-first + synchronization tests of the technician's
/// "Create Customer & Job".
///
/// These run the REAL `JobsRepositoryImpl`, the REAL durable Drift
/// [SyncQueue] and the REAL shared [SyncManager]; only the backend is faked,
/// with the SAME semantics as `technician_customer_job_setup.sql`:
/// * only an active technician may create (admins are refused),
/// * the assignee is resolved from the session, never from the payload,
/// * `job_number` and operational timestamps come from the server; job
///   `created_at` is the timestamp captured when the local create is queued,
/// * customer + job are created together or not at all,
/// * a replay with the same job id returns the existing row — never a second
///   job, a second customer or a second pair of events.
const NewCustomerDraft kDraft = NewCustomerDraft(
  name: 'Anna Weber',
  address: 'Hauptstraße 12',
  phone: '+49 151 23456789',
  city: 'Berlin',
  postalCode: '10115',
  notes: 'Ring twice.',
);

/// Fake of the two technician creation RPCs + the accessible-customers read.
class _TechnicianCreationRemote implements JobsRemoteDataSource {
  _TechnicianCreationRemote({
    this.isAdmin = false,
    this.authorizedTechnicianId = 'emp-me',
    this.allowedCustomerIds = const <String>{},
    this.error,
  });

  /// The caller's session is an admin — the RPCs refuse admins outright.
  final bool isAdmin;

  /// The employee row the server resolves from `auth.uid()`.
  final String? authorizedTechnicianId;

  /// Customers an EXISTING-customer job may be created for (the RPC's 42501
  /// access rule).
  final Set<String> allowedCustomerIds;

  /// Simulates any other server refusal.
  final Object? error;

  /// The server's own clock — the ONLY source of the job timestamps.
  static final DateTime serverNow = DateTime.utc(2026, 10, 11, 8, 0);

  /// The server's `customers` rows, by id.
  final Map<String, NewCustomerDraft> customers = <String, NewCustomerDraft>{};

  /// The server's `jobs` rows, by id.
  final Map<String, Job> jobs = <String, Job>{};

  /// The `job_events` rows the server appended.
  final List<Map<String, Object?>> events = <Map<String, Object?>>[];

  /// RPC attempt counters (a replay counts as an attempt but inserts nothing).
  int createCustomerAndJobCalls = 0;
  int createJobCalls = 0;
  int accessibleCustomerCalls = 0;

  /// Customers an accessible-customers read returns.
  List<AccessibleCustomer> accessibleCustomers = const <AccessibleCustomer>[];

  void _assertActiveTechnician() {
    if (isAdmin || authorizedTechnicianId == null) {
      throw const TechnicianJobCreationRejectedException(
        reason: TechnicianJobRejectReason.unauthorized,
        serverMessage: 'Only an active technician can create a customer and '
            'job.',
      );
    }
  }

  int get _nextJobNumber =>
      jobs.values.fold<int>(
        0,
        (int max, Job job) => job.jobNumber > max ? job.jobNumber : max,
      ) +
      1;

  Job _insertJob({
    required String jobId,
    required String customerId,
    required String jobType,
    required String? description,
    required DateTime createdAt,
  }) {
    final Job created = Job(
      id: jobId,
      jobNumber: _nextJobNumber,
      customerId: customerId,
      assignedEmployeeId: authorizedTechnicianId,
      jobType: jobType,
      description: description,
      status: const JobStatus(JobStatus.assigned),
      assignedAt: serverNow,
      createdAt: createdAt,
      updatedAt: serverNow,
      expiresAt: DateTime.utc(
        createdAt.year + 1,
        createdAt.month,
        createdAt.day,
        createdAt.hour,
        createdAt.minute,
        createdAt.second,
        createdAt.millisecond,
        createdAt.microsecond,
      ),
    );
    jobs[jobId] = created;
    for (final String eventType in <String>['job_created', 'job_assigned']) {
      events.add(<String, Object?>{
        'job_id': jobId,
        'employee_id': authorizedTechnicianId,
        'event_type': eventType,
        'occurred_at': serverNow,
      });
    }
    return created;
  }

  @override
  Future<Job> technicianCreateCustomerAndJob({
    required String jobId,
    required String customerId,
    required NewCustomerDraft customer,
    required String jobType,
    required DateTime createdAt,
    String? description,
  }) async {
    createCustomerAndJobCalls++;
    _assertActiveTechnician();
    if (error != null) {
      throw error!; // ignore: only_throw_errors
    }
    if (!JobCategory.isSupported(jobType)) {
      throw const TechnicianJobCreationRejectedException(
        reason: TechnicianJobRejectReason.invalidInput,
        serverMessage: 'Unsupported job category.',
      );
    }

    // Idempotent replay: the row already exists — return it, insert nothing.
    final Job? existing = jobs[jobId];
    if (existing != null) {
      return existing;
    }

    if (customer.name.trim().isEmpty || customer.address.trim().isEmpty) {
      throw const TechnicianJobCreationRejectedException(
        reason: TechnicianJobRejectReason.invalidInput,
        serverMessage: 'A customer name and address are required.',
      );
    }

    // ONE transaction: the customer row and the job row land together.
    customers[customerId] = customer;
    return _insertJob(
      jobId: jobId,
      customerId: customerId,
      jobType: jobType,
      description: description,
      createdAt: createdAt,
    );
  }

  @override
  Future<Job> technicianCreateJobForCustomer({
    required String jobId,
    required String customerId,
    required String jobType,
    required DateTime createdAt,
    String? description,
  }) async {
    createJobCalls++;
    _assertActiveTechnician();
    if (error != null) {
      throw error!; // ignore: only_throw_errors
    }
    if (!JobCategory.isSupported(jobType)) {
      throw const TechnicianJobCreationRejectedException(
        reason: TechnicianJobRejectReason.invalidInput,
        serverMessage: 'Unsupported job category.',
      );
    }

    final Job? existing = jobs[jobId];
    if (existing != null) {
      return existing;
    }

    if (!customers.containsKey(customerId) &&
        !allowedCustomerIds.contains(customerId)) {
      // The access rule: a customer outside the caller's own work is refused,
      // and no job row is created.
      throw const TechnicianJobCreationRejectedException(
        reason: TechnicianJobRejectReason.unauthorized,
        serverMessage:
            'You are not allowed to create a job for this customer.',
      );
    }

    return _insertJob(
      jobId: jobId,
      customerId: customerId,
      jobType: jobType,
      description: description,
      createdAt: createdAt,
    );
  }

  @override
  Future<List<AccessibleCustomer>> getTechnicianAccessibleCustomers({
    String search = '',
  }) async {
    accessibleCustomerCalls++;
    _assertActiveTechnician();
    return accessibleCustomers;
  }

  // --- Not under test here ----------------------------------------------------

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
  Future<Job> startJob(String jobId) async => throw UnimplementedError();

  @override
  Future<Job> saveWorkDescription({
    required String jobId,
    required String workDescription,
  }) async => throw UnimplementedError();

  @override
  Future<Job> completeJob(String jobId) async => throw UnimplementedError();
}

/// The job-file surface is irrelevant here — swapped so the repository can be
/// constructed without a Supabase client.
class _UnusedFilesRemote implements JobFilesRemoteDataSource {
  @override
  Future<void> authorizeJobFileUpload({required String jobId}) async =>
      throw UnimplementedError();

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

Future<void> _untilQueueDrained() async {
  for (int i = 0; i < 200; i++) {
    if (await sl<SyncQueue>().pendingCount() == 0) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Sync queue did not drain in time.');
}

void main() {
  late AppTestHarness app;
  _SwitchableNetworkInfo? network;

  setUp(() => app = AppTestHarness());
  tearDown(() async {
    await network?.close();
    network = null;
    await app.dispose();
  });

  /// Configures the harness with the REAL jobs repository + durable Drift
  /// sync queue and swaps only the remote data source for the fake RPCs.
  Future<_TechnicianCreationRemote> configureSync({
    required bool online,
    bool isAdmin = false,
    Set<String> allowedCustomerIds = const <String>{},
    Object? error,
    bool switchableNetwork = false,
  }) async {
    await app.configure(
      user: technicianUser,
      withJobsSync: true,
      jobsOnline: online,
    );

    final _TechnicianCreationRemote remote = _TechnicianCreationRemote(
      isAdmin: isAdmin,
      allowedCustomerIds: allowedCustomerIds,
      error: error,
    );
    await sl.unregister<JobsRemoteDataSource>();
    sl.registerSingleton<JobsRemoteDataSource>(remote);

    await sl.unregister<JobFilesRemoteDataSource>();
    sl.registerSingleton<JobFilesRemoteDataSource>(_UnusedFilesRemote());

    if (switchableNetwork) {
      network = _SwitchableNetworkInfo();
      await sl.unregister<NetworkInfo>();
      sl.registerSingleton<NetworkInfo>(network!);
    }

    return remote;
  }

  test(
    'offline creation queues ONE durable operation and reaches no server',
    () async {
      final _TechnicianCreationRemote remote = await configureSync(
        online: false,
      );

      final TechnicianJobCreation result = await sl<JobsRepository>()
          .createTechnicianCustomerAndJob(
            customer: kDraft,
            jobType: JobCategory.kitchenRenovation,
            description: 'New kitchen fronts',
            idempotencyKey: 'form-1',
          );

      // Offline never claims a server confirmation.
      expect(result.isPendingSync, isTrue);
      expect(result.job, isNull);
      expect(result.jobNumber, isNull);
      expect(result.jobId, isNotEmpty);

      // Exactly one operation in the EXISTING queue, carrying the whole unit.
      expect(await sl<SyncQueue>().pendingCount(), 1);
      expect(await sl<SyncQueue>().failedCount(), 0);
      final SyncOperation? op = await sl<SyncQueue>().nextPending();
      expect(op, isNotNull);
      expect(op!.entityType, SyncEntityType.job);
      expect(op.entityId, result.jobId);
      expect(op.type, SyncOperationType.create);
      expect(
        op.payload[JobsRepositoryImpl.actionKey],
        JobsRepositoryImpl.technicianCreateCustomerAndJobAction,
      );
      expect(op.payload[JobsRepositoryImpl.jobIdKey], result.jobId);
      expect(op.payload[JobsRepositoryImpl.jobTypeKey],
          JobCategory.kitchenRenovation);
      expect(op.payload[JobsRepositoryImpl.descriptionKey], 'New kitchen fronts');

      // The customer travels inside the SAME operation, keyed by the real id.
      final Object? customerPayload =
          op.payload[JobsRepositoryImpl.customerKey];
      expect(customerPayload, isA<Map>());
      final NewCustomerDraft queued = NewCustomerDraft.fromPayload(
        Map<String, Object?>.from(customerPayload! as Map),
      );
      expect(queued, kDraft);
      expect(op.payload[JobsRepositoryImpl.customerIdKey], isNotEmpty);
      expect(
        op.payload[JobsRepositoryImpl.customerIdKey],
        isNot(op.payload[JobsRepositoryImpl.jobIdKey]),
      );

      // The client contributes no server identity/number. The local creation
      // timestamp is explicit and matches this create operation's timestamp.
      expect(op.payload.containsKey('assigned_employee_id'), isFalse);
      expect(op.payload.containsKey('job_number'), isFalse);
      expect(op.payload[JobsRepositoryImpl.createdAtKey], isA<String>());
      expect(
        DateTime.parse(op.payload[JobsRepositoryImpl.createdAtKey]! as String)
            .toUtc()
            .millisecondsSinceEpoch ~/
            1000,
        op.createdAt.toUtc().millisecondsSinceEpoch ~/ 1000,
      );
      expect(op.payload.containsKey('assigned_at'), isFalse);

      expect(remote.createCustomerAndJobCalls, 0);
      expect(remote.jobs, isEmpty);
      expect(remote.customers, isEmpty);
    },
  );

  test(
    'retrying the same form offline never queues a second creation',
    () async {
      await configureSync(online: false);

      for (int i = 0; i < 3; i++) {
        await sl<JobsRepository>().createTechnicianCustomerAndJob(
          customer: kDraft,
          jobType: JobCategory.kitchenRenovation,
          idempotencyKey: 'form-1',
        );
      }

      // Same key -> same job id -> same operation id -> no duplicates.
      expect(await sl<SyncQueue>().pendingCount(), 1);
    },
  );

  test('two different forms produce two distinct creations', () async {
    await configureSync(online: false);

    final TechnicianJobCreation first = await sl<JobsRepository>()
        .createTechnicianCustomerAndJob(
          customer: kDraft,
          jobType: JobCategory.kitchenRenovation,
          idempotencyKey: 'form-1',
        );
    final TechnicianJobCreation second = await sl<JobsRepository>()
        .createTechnicianCustomerAndJob(
          customer: kDraft,
          jobType: JobCategory.homeRenovation,
          idempotencyKey: 'form-2',
        );

    expect(first.jobId, isNot(second.jobId));
    expect(await sl<SyncQueue>().pendingCount(), 2);
  });

  test(
    'the queued creation syncs automatically when connectivity returns',
    () async {
      final _TechnicianCreationRemote remote = await configureSync(
        online: false,
        switchableNetwork: true,
      );
      await sl<SyncManager>().start();

      final TechnicianJobCreation result = await sl<JobsRepository>()
          .createTechnicianCustomerAndJob(
            customer: kDraft,
            jobType: JobCategory.homeRenovation,
            description: 'Bathroom tiles',
            idempotencyKey: 'form-1',
          );
      expect(remote.createCustomerAndJobCalls, 0);
      expect(await sl<SyncQueue>().pendingCount(), 1);

      // Internet returns: the engine's own listener drains the queue.
      network!.setOnline(true);
      await _untilQueueDrained();

      expect(await sl<SyncQueue>().failedCount(), 0);
      expect(remote.createCustomerAndJobCalls, 1);

      // Customer AND job exist, linked by the real customer id.
      expect(remote.customers, hasLength(1));
      expect(remote.jobs, hasLength(1));
      final Job job = remote.jobs.values.single;
      expect(job.id, result.jobId);
      expect(job.customerId, remote.customers.keys.single);
      expect(job.customerId, isNot(job.id));
      expect(job.jobType, JobCategory.homeRenovation);
      expect(job.description, 'Bathroom tiles');
      expect(job.status.value, JobStatus.assigned);

      // The assignee is the caller's own employee row, resolved server-side.
      expect(job.assignedEmployeeId, 'emp-me');

      // The server still stamps operational times; retention uses the time
      // captured when the local creation entered the durable queue.
      expect(job.jobNumber, 1);
      expect(job.assignedAt, _TechnicianCreationRemote.serverNow);
      expect(
        job.expiresAt,
        DateTime.utc(
          job.createdAt.year + 1,
          job.createdAt.month,
          job.createdAt.day,
          job.createdAt.hour,
          job.createdAt.minute,
          job.createdAt.second,
          job.createdAt.millisecond,
          job.createdAt.microsecond,
        ),
      );

      // The two append-only events, attributed to the caller.
      expect(remote.events, hasLength(2));
      expect(
        remote.events.map((Map<String, Object?> e) => e['event_type']),
        <String>['job_created', 'job_assigned'],
      );
      expect(remote.events.every((Map<String, Object?> e) =>
          e['employee_id'] == 'emp-me'), isTrue);
    },
  );

  test(
    'online creation returns the authoritative row and closes the operation',
    () async {
      final _TechnicianCreationRemote remote = await configureSync(
        online: true,
      );
      await sl<ConnectivityService>().start();

      final TechnicianJobCreation result = await sl<JobsRepository>()
          .createTechnicianCustomerAndJob(
            customer: kDraft,
            jobType: JobCategory.kitchenRenovation,
            idempotencyKey: 'form-1',
          );

      expect(result.isCreated, isTrue);
      expect(result.jobNumber, 1);
      expect(result.job!.assignedEmployeeId, 'emp-me');
      expect(result.job!.customerId, remote.customers.keys.single);

      // The queued operation is settled — nothing left to push or retry.
      expect(await sl<SyncQueue>().pendingCount(), 0);
      expect(await sl<SyncQueue>().failedCount(), 0);
      expect(remote.createCustomerAndJobCalls, 1);
    },
  );

  test(
    'a replayed creation is idempotent: one customer, one job, two events',
    () async {
      final _TechnicianCreationRemote remote = await configureSync(
        online: true,
      );
      await sl<ConnectivityService>().start();

      final TechnicianJobCreation first = await sl<JobsRepository>()
          .createTechnicianCustomerAndJob(
            customer: kDraft,
            jobType: JobCategory.kitchenRenovation,
            idempotencyKey: 'form-1',
          );
      expect(first.jobNumber, 1);

      // Replay the SAME logical change (lost ack / duplicated push) with a
      // fresh operation id, exactly as the sync engine would.
      final SyncOperation? queued = await sl<SyncQueue>().nextPending();
      expect(queued, isNull);
      await sl<SyncQueue>().enqueue(
        SyncOperation(
          id: 'replay-op',
          entityType: SyncEntityType.job,
          entityId: first.jobId,
          type: SyncOperationType.create,
          payload: <String, Object?>{
            JobsRepositoryImpl.actionKey:
                JobsRepositoryImpl.technicianCreateCustomerAndJobAction,
            JobsRepositoryImpl.jobIdKey: first.jobId,
            JobsRepositoryImpl.customerIdKey: first.job!.customerId,
            JobsRepositoryImpl.jobTypeKey: JobCategory.kitchenRenovation,
            JobsRepositoryImpl.descriptionKey: null,
            JobsRepositoryImpl.createdAtKey:
                first.job!.createdAt.toUtc().toIso8601String(),
            JobsRepositoryImpl.customerKey: kDraft.toPayload(),
          },
          createdAt: DateTime.utc(2026, 10, 15, 9),
        ),
      );
      await sl<SyncProcessor>().processPendingOperations();
      await _untilQueueDrained();

      expect(await sl<SyncQueue>().failedCount(), 0);
      expect(remote.createCustomerAndJobCalls, 2);
      // Nothing was duplicated.
      expect(remote.customers, hasLength(1));
      expect(remote.jobs, hasLength(1));
      expect(remote.jobs.values.single.jobNumber, 1);
      expect(remote.jobs.values.single.createdAt, first.job!.createdAt);
      expect(
        remote.jobs.values.single.expiresAt,
        first.job!.expiresAt,
      );
      expect(remote.events, hasLength(2));
    },
  );

  test(
    'offline creation timestamp wins over a later sync-queue ordering time',
    () async {
      final _TechnicianCreationRemote remote = _TechnicianCreationRemote(
        allowedCustomerIds: const <String>{'customer-1'},
      );
      final SyncOperation operation = SyncOperation(
        id: 'offline-create-op',
        entityType: SyncEntityType.job,
        entityId: 'job-1',
        type: SyncOperationType.create,
        payload: <String, Object?>{
          JobsRepositoryImpl.actionKey:
              JobsRepositoryImpl.technicianCreateJobAction,
          JobsRepositoryImpl.jobIdKey: 'job-1',
          JobsRepositoryImpl.customerIdKey: 'customer-1',
          JobsRepositoryImpl.jobTypeKey: JobCategory.homeRenovation,
          JobsRepositoryImpl.descriptionKey: null,
          JobsRepositoryImpl.createdAtKey: '2026-10-01T00:00:00.000Z',
        },
        createdAt: DateTime.utc(2026, 10, 15),
      );

      final result = await JobSyncHandler(remote: remote).push(operation);

      expect(result.success, isTrue);
      expect(remote.jobs['job-1']!.createdAt, DateTime.utc(2026, 10, 1));
      expect(remote.jobs['job-1']!.expiresAt, DateTime.utc(2027, 10, 1));
    },
  );

  test(
    'legacy create queue rows fall back to their original create time',
    () async {
      final _TechnicianCreationRemote remote = _TechnicianCreationRemote(
        allowedCustomerIds: const <String>{'customer-1'},
      );
      final SyncOperation operation = SyncOperation(
        id: 'legacy-offline-create-op',
        entityType: SyncEntityType.job,
        entityId: 'job-legacy',
        type: SyncOperationType.create,
        payload: <String, Object?>{
          JobsRepositoryImpl.actionKey:
              JobsRepositoryImpl.technicianCreateJobAction,
          JobsRepositoryImpl.jobIdKey: 'job-legacy',
          JobsRepositoryImpl.customerIdKey: 'customer-1',
          JobsRepositoryImpl.jobTypeKey: JobCategory.homeRenovation,
          JobsRepositoryImpl.descriptionKey: null,
        },
        // Legacy _enqueueTechnicianCreation wrote this at task creation.
        createdAt: DateTime.utc(2026, 10, 1),
      );

      final result = await JobSyncHandler(remote: remote).push(operation);

      expect(result.success, isTrue);
      expect(remote.jobs['job-legacy']!.createdAt, DateTime.utc(2026, 10, 1));
      expect(remote.jobs['job-legacy']!.expiresAt, DateTime.utc(2027, 10, 1));
    },
  );

  test(
    'a refused creation stays failed and retryable, never synced',
    () async {
      // An admin session: both technician RPCs refuse it with 42501.
      final _TechnicianCreationRemote remote = await configureSync(
        online: true,
        isAdmin: true,
      );
      await sl<ConnectivityService>().start();

      await expectLater(
        () => sl<JobsRepository>().createTechnicianCustomerAndJob(
          customer: kDraft,
          jobType: JobCategory.kitchenRenovation,
          idempotencyKey: 'form-1',
        ),
        throwsA(
          isA<TechnicianJobCreationRejectedException>().having(
            (TechnicianJobCreationRejectedException e) => e.reason,
            'reason',
            TechnicianJobRejectReason.unauthorized,
          ),
        ),
      );

      // Nothing was created and the operation stays in the queue.
      expect(remote.jobs, isEmpty);
      expect(remote.customers, isEmpty);
      expect(await sl<SyncQueue>().pendingCount(), 1);
    },
  );

  test(
    'an existing customer outside the technician\'s own jobs is refused',
    () async {
      final _TechnicianCreationRemote remote = await configureSync(
        online: true,
        allowedCustomerIds: <String>{'cust-mine'},
      );
      await sl<ConnectivityService>().start();

      // Allowed: the job is created for that customer.
      final TechnicianJobCreation allowed = await sl<JobsRepository>()
          .createTechnicianJobForCustomer(
            customerId: 'cust-mine',
            jobType: JobCategory.homeRenovation,
            idempotencyKey: 'form-a',
          );
      expect(allowed.isCreated, isTrue);
      expect(allowed.job!.customerId, 'cust-mine');
      expect(allowed.job!.assignedEmployeeId, 'emp-me');
      // No customer row was invented for the existing customer.
      expect(remote.customers, isEmpty);

      // Refused: another customer's id — the server says 42501.
      await expectLater(
        () => sl<JobsRepository>().createTechnicianJobForCustomer(
          customerId: 'cust-somebody-else',
          jobType: JobCategory.homeRenovation,
          idempotencyKey: 'form-b',
        ),
        throwsA(
          isA<TechnicianJobCreationRejectedException>().having(
            (TechnicianJobCreationRejectedException e) => e.reason,
            'reason',
            TechnicianJobRejectReason.unauthorized,
          ),
        ),
      );
      expect(remote.jobs, hasLength(1));
    },
  );

  test('an unsupported category never leaves the device', () async {
    final _TechnicianCreationRemote remote = await configureSync(
      online: true,
    );

    await expectLater(
      () => sl<JobsRepository>().createTechnicianCustomerAndJob(
        customer: kDraft,
        jobType: 'painting',
        idempotencyKey: 'form-1',
      ),
      throwsA(isA<ArgumentError>()),
    );

    expect(remote.createCustomerAndJobCalls, 0);
    // The client-side guard fires BEFORE anything is queued.
    expect(await sl<SyncQueue>().pendingCount(), 0);
  });

  test('an empty idempotency key is refused', () async {
    await configureSync(online: true);

    await expectLater(
      () => sl<JobsRepository>().createTechnicianCustomerAndJob(
        customer: kDraft,
        jobType: JobCategory.kitchenRenovation,
        idempotencyKey: '   ',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('the accessible-customer read is passed through unchanged', () async {
    final _TechnicianCreationRemote remote = await configureSync(
      online: true,
    );
    remote.accessibleCustomers = const <AccessibleCustomer>[
      AccessibleCustomer(id: 'cust-1', name: 'Anna Weber', phone: '+49 151 1'),
    ];

    final List<AccessibleCustomer> customers = await sl<JobsRepository>()
        .getAccessibleCustomers(search: 'anna');

    expect(remote.accessibleCustomerCalls, 1);
    expect(customers, hasLength(1));
    expect(customers.single.id, 'cust-1');
  });
}
