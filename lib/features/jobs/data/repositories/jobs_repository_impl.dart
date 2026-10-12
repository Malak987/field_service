// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:field_service/core/network/network_info.dart';
import 'package:field_service/core/utils/logger.dart';
import 'package:field_service/core/storage/file_storage.dart';
import 'package:field_service/core/storage/local_file_storage.dart';
import 'package:field_service/core/sync/sync_operation.dart';
import 'package:field_service/core/sync/sync_processor.dart';
import 'package:field_service/core/sync/sync_queue.dart';
import 'package:field_service/core/database/app_database.dart';
import 'package:field_service/core/database/tables/job_files_table.dart';
import 'package:field_service/features/jobs/data/datasources/job_files_remote_data_source.dart';
import 'package:field_service/features/jobs/data/datasources/jobs_remote_data_source.dart';
import 'package:field_service/features/jobs/data/models/job_file_model.dart';
import 'package:field_service/features/jobs/domain/entities/accessible_customer.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/domain/entities/new_customer_draft.dart';
import 'package:field_service/features/jobs/domain/entities/technician_job_creation.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Data-layer implementation of [JobsRepository].
///
/// Reads delegate to [JobsRemoteDataSource] (visibility is enforced by
/// Supabase RLS). The write paths are offline-first and follow the exact
/// contract of the Customers feature: persist the change locally first, then
/// give the shared [SyncProcessor] a nudge. One engine, one queue — no
/// second sync system.
///
/// * [startJob] queues a `job` update operation; the `start_job` RPC applies
///   status + server timestamps + event atomically and idempotently.
/// * [completeJob] is the ONE online-only write: the completion verdict
///   depends on server-side facts, so without connectivity it throws
///   [JobCompletionOfflineException] instead of queueing; online the
///   `complete_job` RPC validates all conditions, applies the status, the
///   server `completed_at` and the `job_completed` event atomically.
/// * [addBeforePhoto] copies the picked image into app-owned storage via
///   [LocalFileStorage] (which registers the local `job_files` row with a
///   stable id + automatic capture timestamp and enqueues the `jobFile`
///   upload operation); [JobFileSyncHandler] later uploads the bytes with
///   upsert semantics and registers the file through the idempotent
///   `register_job_file` RPC.
class JobsRepositoryImpl implements JobsRepository {
  JobsRepositoryImpl({
    required JobsRemoteDataSource remoteDataSource,
    required SyncQueue syncQueue,
    required SyncProcessor syncProcessor,
    required LocalFileStorage localFileStorage,
    required FileStorage fileStorage,
    required JobFilesRemoteDataSource filesRemoteDataSource,
    required NetworkInfo networkInfo,
    Uuid? uuid,
    DateTime Function()? now,
  }) : _remoteDataSource = remoteDataSource,
       _syncQueue = syncQueue,
       _syncProcessor = syncProcessor,
       _localFileStorage = localFileStorage,
       _fileStorage = fileStorage,
       _filesRemote = filesRemoteDataSource,
       _networkInfo = networkInfo,
       _uuid = uuid ?? const Uuid(),
       _now = now ?? (() => DateTime.now().toUtc());

  final JobsRemoteDataSource _remoteDataSource;
  final SyncQueue _syncQueue;
  final SyncProcessor _syncProcessor;
  final LocalFileStorage _localFileStorage;
  final FileStorage _fileStorage;
  final JobFilesRemoteDataSource _filesRemote;
  final NetworkInfo _networkInfo;
  final Uuid _uuid;
  final DateTime Function() _now;

  /// Payload key identifying a queued job action; the value is the action
  /// name the [JobSyncHandler] understands. Kept here so the enqueue side
  /// and the push side share one schema.
  static const String actionKey = 'action';

  /// The `start_job` action: start the job on the server (status,
  /// `started_at`, `job_started` event — all server-side).
  static const String startJobAction = 'start_job';

  /// The `save_work_description` action: store the technician's work
  /// description on the server (column update + `work_description_added`
  /// event — all server-side).
  static const String saveWorkDescriptionAction = 'save_work_description';

  /// Payload key carrying the work description text of a queued
  /// [saveWorkDescriptionAction] operation. The text itself is the durable
  /// local copy while offline.
  static const String workDescriptionKey = 'work_description';

  // --- Technician "Create Customer & Job" payload schema ---------------------
  //
  // Declared next to the other payload keys so the enqueue side (this class)
  // and the replay side (`JobSyncHandler`) share ONE schema: a queued
  // operation always carries exactly the arguments its RPC needs.

  /// The `technician_create_customer_and_job` action: create the customer and
  /// its job as one server-side unit.
  static const String technicianCreateCustomerAndJobAction =
      'technician_create_customer_and_job';

  /// The `technician_create_job_for_customer` action: create a job for an
  /// existing customer the technician may work for.
  static const String technicianCreateJobAction = 'technician_create_job';

  /// Payload key of the client-generated `jobs.id` (the idempotency key of
  /// the RPC). Also the operation's `entityId`.
  static const String jobIdKey = 'job_id';

  /// Payload key of the stable `customers.id` the job is linked to.
  static const String customerIdKey = 'customer_id';

  /// Payload key of the job category (`jobs.job_type`).
  static const String jobTypeKey = 'job_type';

  /// Payload key of the job description (`jobs.description`).
  static const String descriptionKey = 'description';

  /// Payload key of the nested customer draft (only for
  /// [technicianCreateCustomerAndJobAction]).
  static const String customerKey = 'customer';

  /// Fixed namespace UUID (RFC 4122 DNS namespace) for the deterministic
  /// ids derived from the caller's idempotency key via `uuid` v5.
  ///
  /// A plain constant rather than a `Namespace` enum reference so this
  /// derivation never depends on a package export detail.
  static const String _idNamespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

  @override
  Future<List<Job>> getJobs() {
    return _remoteDataSource.getJobs();
  }

  @override
  Future<Job> getJobById(String id) {
    return _remoteDataSource.getJobById(id);
  }

  @override
  Future<void> updateJobStatus({
    required String jobId,
    required String status,
  }) {
    return _remoteDataSource.updateJobStatus(jobId: jobId, status: status);
  }

  @override
  Future<Job> createJob({
    required String customerId,
    required String jobType,
    String? description,
    required String assignedEmployeeId,
  }) {
    // Client-side pre-flight guard (defense in depth): the business supports
    // exactly two categories. The server (`create_job` RPC + table CHECK
    // constraint) remains the authoritative validator — this only keeps an
    // obviously invalid value from leaving the device.
    if (!JobCategory.isSupported(jobType)) {
      throw ArgumentError.value(jobType, 'jobType', 'Unsupported job category');
    }

    // Direct RPC by design (see the domain contract): job number, assignment
    // timestamp and events are server-authoritative — nothing to queue.
    return _remoteDataSource.createJob(
      customerId: customerId,
      jobType: jobType,
      description: description,
      assignedEmployeeId: assignedEmployeeId,
    );
  }

  @override
  Future<JobCustomerInfo?> getJobCustomerInfo(String jobId) {
    return _remoteDataSource.getJobCustomerInfo(jobId);
  }

  // --- Technician: create customer & job --------------------------------------
  //
  // Offline-first on the EXISTING stack, and deliberately ONE operation for
  // the whole logical unit:
  //
  //   1. derive STABLE ids from the caller's idempotency key (a v5 UUID, so
  //      every retry of the same form reuses exactly the same job id and the
  //      same queue row),
  //   2. enqueue ONE durable `job` operation carrying the full draft — this
  //      is the local copy that survives a process kill,
  //   3. online: call the RPC and return the authoritative row; offline:
  //      report `queued` and let the shared `SyncManager` push it later.
  //
  // The RPC itself is idempotent on the job id, so step 3 racing with a
  // background push (or a replay after a lost acknowledgement) can never
  // create a second job or a second pair of events.

  @override
  Future<List<AccessibleCustomer>> getAccessibleCustomers({
    String search = '',
  }) {
    return _remoteDataSource.getTechnicianAccessibleCustomers(search: search);
  }

  @override
  Future<TechnicianJobCreation> createTechnicianCustomerAndJob({
    required NewCustomerDraft customer,
    required String jobType,
    String? description,
    required String idempotencyKey,
  }) async {
    // Client-side pre-flight guard (defense in depth): the business supports
    // exactly two categories and the fields have an agreed bound. The server
    // re-validates every security-relevant rule on its own.
    _requireSupportedCategory(jobType);
    _requireWithinLimit(
      value: customer.name,
      limit: JobsRepository.maxCustomerNameLength,
      field: 'customer.name',
    );
    _requireWithinLimit(
      value: customer.address,
      limit: JobsRepository.maxCustomerAddressLength,
      field: 'customer.address',
    );
    _requireWithinLimit(
      value: customer.phone,
      limit: JobsRepository.maxCustomerPhoneLength,
      field: 'customer.phone',
    );
    _requireWithinLimit(
      value: customer.email,
      limit: JobsRepository.maxCustomerEmailLength,
      field: 'customer.email',
    );
    _requireWithinLimit(
      value: customer.city,
      limit: JobsRepository.maxCustomerCityLength,
      field: 'customer.city',
    );
    _requireWithinLimit(
      value: customer.postalCode,
      limit: JobsRepository.maxCustomerPostalCodeLength,
      field: 'customer.postalCode',
    );
    _requireWithinLimit(
      value: customer.notes,
      limit: JobsRepository.maxCustomerNotesLength,
      field: 'customer.notes',
    );

    final String jobId = _stableId(idempotencyKey, 'job');
    final String customerId = _stableId(idempotencyKey, 'customer');
    final String? cleanDescription = _cleanDescription(description);

    await _enqueueTechnicianCreation(
      idempotencyKey: idempotencyKey,
      jobId: jobId,
      payload: <String, Object?>{
        actionKey: technicianCreateCustomerAndJobAction,
        jobIdKey: jobId,
        customerIdKey: customerId,
        jobTypeKey: jobType,
        descriptionKey: cleanDescription,
        customerKey: customer.toPayload(),
      },
    );

    return _submitTechnicianCreation(
      jobId: jobId,
      idempotencyKey: idempotencyKey,
      push: () => _remoteDataSource.technicianCreateCustomerAndJob(
        jobId: jobId,
        customerId: customerId,
        customer: customer,
        jobType: jobType,
        description: cleanDescription,
      ),
    );
  }

  @override
  Future<TechnicianJobCreation> createTechnicianJobForCustomer({
    required String customerId,
    required String jobType,
    String? description,
    required String idempotencyKey,
  }) async {
    _requireSupportedCategory(jobType);
    if (customerId.trim().isEmpty) {
      throw ArgumentError.value(
        customerId,
        'customerId',
        'A customer id is required',
      );
    }

    final String jobId = _stableId(idempotencyKey, 'job');
    final String? cleanDescription = _cleanDescription(description);

    await _enqueueTechnicianCreation(
      idempotencyKey: idempotencyKey,
      jobId: jobId,
      payload: <String, Object?>{
        actionKey: technicianCreateJobAction,
        jobIdKey: jobId,
        customerIdKey: customerId.trim(),
        jobTypeKey: jobType,
        descriptionKey: cleanDescription,
      },
    );

    return _submitTechnicianCreation(
      jobId: jobId,
      idempotencyKey: idempotencyKey,
      push: () => _remoteDataSource.technicianCreateJobForCustomer(
        jobId: jobId,
        customerId: customerId.trim(),
        jobType: jobType,
        description: cleanDescription,
      ),
    );
  }

  /// Derives a stable UUID from [idempotencyKey] and [purpose].
  ///
  /// Deterministic on purpose: retrying the same form must reuse the same
  /// job/customer/operation ids, otherwise a lost acknowledgement would
  /// produce a second job. A different form instance uses a different key.
  String _stableId(String idempotencyKey, String purpose) {
    final String key = idempotencyKey.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'An idempotency key is required',
      );
    }
    return _uuid.v5(_idNamespace, 'field-service:$purpose:$key');
  }

  /// Persists the creation as ONE durable queue operation.
  ///
  /// The operation id is derived from the same idempotency key, so a retried
  /// enqueue is a no-op (`SyncQueue.enqueue` is `DoNothing` on `id`) — a
  /// double tap or a re-submitted form can never queue the creation twice.
  Future<void> _enqueueTechnicianCreation({
    required String idempotencyKey,
    required String jobId,
    required Map<String, Object?> payload,
  }) {
    return _syncQueue.enqueue(
      SyncOperation(
        id: _stableId(idempotencyKey, 'operation'),
        entityType: SyncEntityType.job,
        entityId: jobId,
        type: SyncOperationType.create,
        payload: payload,
        createdAt: _now(),
      ),
    );
  }

  /// Pushes the queued creation now when the device is online.
  ///
  /// Online: the RPC answer is authoritative — the caller receives the real
  /// row (with the database-generated job number) and the queue row is
  /// marked synced. Offline: nothing is claimed to be saved on the server;
  /// the caller receives `queued` and the shared engine pushes it as soon as
  /// connectivity returns. A failed push leaves the operation queued for the
  /// existing retry path (connectivity event / Retry action).
  Future<TechnicianJobCreation> _submitTechnicianCreation({
    required String jobId,
    required String idempotencyKey,
    required Future<Job> Function() push,
  }) async {
    if (!await _networkInfo.isConnected) {
      _nudgeSyncProcessor();
      return TechnicianJobCreation.queued(jobId: jobId);
    }

    try {
      final Job job = await push();
      // Best effort: the engine may already have pushed the same operation
      // (the RPC is idempotent, so that is harmless). A bookkeeping failure
      // here must never mask a successful creation.
      try {
        await _syncQueue.markSynced(_stableId(idempotencyKey, 'operation'));
      } catch (error, stackTrace) {
        AppLogger.warning(
          'The queued technician job creation could not be marked synced '
          'after a successful push.',
          error: error,
          stackTrace: stackTrace,
        );
      }
      return TechnicianJobCreation.created(job);
    } catch (error, stackTrace) {
      AppLogger.warning(
        'The technician job creation could not be pushed; it stays queued '
        'for the next sync.',
        error: error,
        stackTrace: stackTrace,
      );
      // Keep the durable operation for the retry path and rethrow so the UI
      // can explain the refusal instead of pretending it succeeded.
      _nudgeSyncProcessor();
      rethrow;
    }
  }

  /// Trims the description and normalizes "blank" to `null` (the RPC stores
  /// `NULLIF(TRIM(...), '')` anyway; this keeps the queued payload clean).
  static String? _cleanDescription(String? description) {
    final String trimmed = description?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  void _requireSupportedCategory(String jobType) {
    if (!JobCategory.isSupported(jobType)) {
      throw ArgumentError.value(
        jobType,
        'jobType',
        'Unsupported job category',
      );
    }
  }

  void _requireWithinLimit({
    required String? value,
    required int limit,
    required String field,
  }) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.length > limit) {
      throw ArgumentError.value(
        value,
        field,
        'Exceeds the maximum length of $limit characters',
      );
    }
  }

  @override
  Future<void> startJob(String jobId) async {
    // Duplicate-start guard (client side): a start that is already queued,
    // in flight or awaiting retry must not be enqueued again. The server's
    // idempotent RPC is the final backstop either way.
    final Set<String> unfinished = await _syncQueue.unfinishedEntityIds(
      SyncEntityType.job,
    );
    if (unfinished.contains(jobId)) {
      throw JobAlreadyStartedException(jobId);
    }

    await _syncQueue.enqueue(
      SyncOperation(
        id: _uuid.v4(),
        entityType: SyncEntityType.job,
        entityId: jobId,
        type: SyncOperationType.update,
        // Deliberately NO timestamp in the payload: `started_at` is
        // database-generated by the RPC; the client only names the action.
        payload: <String, Object?>{actionKey: startJobAction},
        createdAt: _now(),
      ),
    );

    // Fire-and-forget, same convention as the Customers feature: online, the
    // shared engine pushes immediately; offline it finds nothing it can do
    // and the operation simply stays queued.
    unawaited(
      _syncProcessor.processPendingOperations().catchError((Object _) {
        // Sync runs never crash the write path; the operation stays queued.
      }),
    );
  }

  @override
  Future<void> saveWorkDescription({
    required String jobId,
    required String workDescription,
  }) async {
    // Client-side pre-flight (defense in depth): the server trims and
    // re-validates regardless — this only keeps obviously invalid text from
    // entering the durable queue.
    final String clean = workDescription.trim();
    if (clean.isEmpty) {
      throw ArgumentError.value(
        workDescription,
        'workDescription',
        'Work description cannot be empty',
      );
    }
    if (clean.length > JobsRepository.maxWorkDescriptionLength) {
      throw ArgumentError.value(
        workDescription,
        'workDescription',
        'Work description exceeds the maximum length',
      );
    }

    await _syncQueue.enqueue(
      SyncOperation(
        id: _uuid.v4(),
        entityType: SyncEntityType.job,
        entityId: jobId,
        type: SyncOperationType.update,
        // Deliberately NO timestamp and NO employee id in the payload: the
        // RPC resolves the caller from auth.uid() and stamps its own time.
        // The trimmed text travels in the payload — the queue row doubles
        // as the durable local copy while offline.
        payload: <String, Object?>{
          actionKey: saveWorkDescriptionAction,
          workDescriptionKey: clean,
        },
        createdAt: _now(),
      ),
    );

    // Same convention as startJob: nudge the shared engine; offline the
    // operation simply stays queued until connectivity returns.
    unawaited(
      _syncProcessor.processPendingOperations().catchError((Object _) {
        // Sync runs never crash the write path; the operation stays queued.
      }),
    );
  }

  // --- Complete Job -------------------------------------------------------------
  //
  // The FINAL workflow step is deliberately NOT offline-queued, unlike the
  // steps before it: the completion decision depends on facts only the
  // server knows (registered before/after photos, the stored work
  // description, the registered signature). Marking a job completed locally
  // before the server confirms would be a false state — so without
  // connectivity the call fails fast with [JobCompletionOfflineException]
  // and the job stays `in_progress`. Online, the `complete_job` RPC is the
  // single authority: it re-validates every condition, applies the status,
  // the server-generated `completed_at` and exactly one `job_completed`
  // event atomically, and is idempotent against retries.

  @override
  Future<Job> completeJob(String jobId) async {
    if (!await _networkInfo.isConnected) {
      // Authoritative completion needs the server's verdict — never invent
      // a local completion (no local status flip, no local event).
      throw const JobCompletionOfflineException();
    }

    // Direct RPC by design: only the job id travels. Identity, timestamps
    // and the event are server-authoritative — nothing to queue.
    return _remoteDataSource.completeJob(jobId);
  }

  // --- Job photos (before / after) --------------------------------------------
  //
  // Before Photos and After Photos are the SAME offline-first write path —
  // only the `file_type` differs. `LocalFileStorage`, the durable sync queue
  // and `JobFileSyncHandler` (Storage upload + `register_job_file` RPC) are
  // file-type generic already; the server RPC is the authority for
  // ownership, role, `in_progress` and idempotent events of the matching
  // kind (`before_photo_captured` / `after_photo_captured`).

  Future<String> _addJobPhoto({
    required String jobId,
    required String pickedFilePath,
    required JobFileType fileType,
  }) async {
    final File source = File(pickedFilePath);
    if (!await source.exists()) {
      throw StateError('The picked photo is not readable: $pickedFilePath');
    }

    // LocalFileStorage copies the bytes into app-owned storage immediately
    // (the camera/gallery temp path may vanish at any time), registers the
    // local `job_files` row with the stable id + automatic capture time and
    // enqueues the upload — all in one call, all offline-safe.
    final String fileId = await _localFileStorage.storeFile(
      source: source,
      jobId: jobId,
      fileType: fileType,
      capturedAt: _now(),
      mimeType: _mimeTypeFor(pickedFilePath),
    );

    // Online the shared engine pushes right away; offline the operation
    // stays queued (stable id ⇒ retries never duplicate anything).
    unawaited(
      _syncProcessor.processPendingOperations().catchError((Object _) {
        // Sync runs never crash the write path; the operation stays queued.
      }),
    );

    return fileId;
  }

  @override
  Future<String> addBeforePhoto({
    required String jobId,
    required String pickedFilePath,
  }) {
    return _addJobPhoto(
      jobId: jobId,
      pickedFilePath: pickedFilePath,
      fileType: JobFileType.before,
    );
  }

  @override
  Future<String> addAfterPhoto({
    required String jobId,
    required String pickedFilePath,
  }) {
    return _addJobPhoto(
      jobId: jobId,
      pickedFilePath: pickedFilePath,
      fileType: JobFileType.after,
    );
  }

  Future<List<JobFile>> _getPhotosByType(
    String jobId,
    JobFileType fileType,
  ) async {
    final List<LocalJobFile> localRows = await _localFileStorage.filesForJob(
      jobId,
    );
    final List<JobFile> local = localRows
        .where((LocalJobFile row) => row.fileType == fileType.name)
        .map(JobFileModel.fromLocal)
        .toList();

    return _mergeWithRemote(jobId: jobId, fileType: fileType, local: local);
  }

  @override
  Future<List<JobFile>> getBeforePhotos(String jobId) {
    return _getPhotosByType(jobId, JobFileType.before);
  }

  @override
  Future<List<JobFile>> getAfterPhotos(String jobId) {
    return _getPhotosByType(jobId, JobFileType.after);
  }

  Stream<List<JobFile>> _watchPhotosByType(String jobId, JobFileType fileType) {
    late final StreamController<List<JobFile>> controller;
    StreamSubscription<List<LocalJobFile>>? subscription;
    List<JobFile> remoteOnly = const <JobFile>[];
    bool cancelled = false;

    void emitLocal(List<LocalJobFile> rows) {
      if (cancelled || controller.isClosed) {
        return;
      }
      final List<JobFile> local = rows
          .where((LocalJobFile row) => row.fileType == fileType.name)
          .map(JobFileModel.fromLocal)
          .toList();
      final Set<String> localIds = local.map((JobFile file) => file.id).toSet();
      final List<JobFile> merged = <JobFile>[
        ...local,
        ...remoteOnly.where((JobFile file) => !localIds.contains(file.id)),
      ];
      merged.sort(
        (JobFile a, JobFile b) => a.capturedAt.compareTo(b.capturedAt),
      );
      controller.add(merged);
    }

    controller = StreamController<List<JobFile>>(
      onListen: () {
        subscription = _localFileStorage
            .watchFilesForJob(jobId)
            .listen(emitLocal);

        // Best-effort merge with backend-registered photos (captured on
        // another device). Offline this simply stays local — a captured
        // photo is never hidden because there is no signal.
        unawaited(
          _filesRemote
              .getJobFilesByType(jobId, fileType.name)
              .then((List<JobFile> remote) {
                if (cancelled) {
                  return;
                }
                remoteOnly = remote;
                unawaited(_localFileStorage.filesForJob(jobId).then(emitLocal));
              })
              .catchError((Object error, StackTrace stackTrace) {
                // Offline or unauthorized: local rows are still shown — but
                // never silently: a broken remote read (mapping, RLS,
                // network) must be diagnosable from the logs.
                AppLogger.warning(
                  'Remote job files could not be merged for job $jobId '
                  '(${fileType.name}); showing local rows only.',
                  error: error,
                  stackTrace: stackTrace,
                );
              }),
        );
      },
      onCancel: () async {
        cancelled = true;
        await subscription?.cancel();
      },
    );

    return controller.stream;
  }

  @override
  Stream<List<JobFile>> watchBeforePhotos(String jobId) {
    return _watchPhotosByType(jobId, JobFileType.before);
  }

  @override
  Stream<List<JobFile>> watchAfterPhotos(String jobId) {
    return _watchPhotosByType(jobId, JobFileType.after);
  }

  // --- Customer signature ------------------------------------------------------
  //
  // The customer signature is the third file kind on the SAME generic
  // job-file path (`file_type = 'signature'`): `LocalFileStorage` persists
  // the rendered PNG bytes, the durable sync queue carries the upload and
  // `JobFileSyncHandler` pushes Storage object + `register_job_file` RPC —
  // the server appends exactly one `signature_captured` event.

  @override
  Future<String> captureCustomerSignature({
    required String jobId,
    required Uint8List signatureImage,
  }) async {
    // Defense in depth: the cubit/use case already refuse empty drawings —
    // nothing empty ever reaches the durable queue.
    if (signatureImage.isEmpty) {
      throw ArgumentError.value(
        signatureImage,
        'signatureImage',
        'The signature image is empty',
      );
    }

    final String fileId = await _localFileStorage.storeBytes(
      bytes: signatureImage,
      jobId: jobId,
      fileType: JobFileType.signature,
      fileName: 'signature',
      extension: '.png',
      capturedAt: _now(),
      mimeType: 'image/png',
    );

    // Online the shared engine pushes right away; offline the operation
    // stays queued (stable id ⇒ retries never duplicate anything).
    unawaited(
      _syncProcessor.processPendingOperations().catchError((Object _) {
        // Sync runs never crash the write path; the operation stays queued.
      }),
    );

    return fileId;
  }

  @override
  Future<List<JobFile>> getSignatureFiles(String jobId) {
    return _getPhotosByType(jobId, JobFileType.signature);
  }

  @override
  Stream<List<JobFile>> watchSignatureFiles(String jobId) {
    return _watchPhotosByType(jobId, JobFileType.signature);
  }

  @override
  Future<Uint8List?> readPhotoBytes(JobFile file) async {
    final String? localPath = file.localPath;
    if (localPath != null) {
      final List<int>? bytes = await _fileStorage.read(localPath);
      if (bytes != null) {
        return Uint8List.fromList(bytes);
      }
      // The local copy is gone (e.g. the OS reclaimed space) but the file
      // is confirmed remote: fall through to the Storage download instead
      // of hiding a synced photo.
    }

    final String? remotePath = file.remotePath;
    if (remotePath == null) {
      return null;
    }

    try {
      return await _filesRemote.downloadPhotoBytes(remotePath);
    } catch (error, stackTrace) {
      // Offline or the object vanished: nothing to display. The tile shows
      // a placeholder; nothing about the record itself changes — but the
      // reason is logged, never silently swallowed.
      AppLogger.warning(
        'Photo bytes could not be downloaded for file ${file.id}.',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  @override
  Future<Set<String>> failedJobFileIds() async {
    final List<SyncOperation> failures = await _syncQueue.recentFailures();
    return failures
        .where((SyncOperation op) => op.entityType == SyncEntityType.jobFile)
        .map((SyncOperation op) => op.entityId)
        .toSet();
  }

  @override
  Future<void> retryFailedSyncs() async {
    await _syncProcessor.retryFailedOperations();
  }

  // --- Helpers ------------------------------------------------------------------

  /// Fire-and-forget nudge of the shared sync engine (same convention as
  /// [startJob]): online it pushes immediately, offline it finds nothing it
  /// can do and the operation simply stays queued. A sync run never crashes
  /// the write path.
  void _nudgeSyncProcessor() {
    unawaited(
      _syncProcessor.processPendingOperations().catchError((Object _) {
        // Sync runs never crash the write path; the operation stays queued.
      }),
    );
  }

  /// Merges locally registered photos with backend-registered ones
  /// (deduplicated by the stable file id, ordered by capture time).
  Future<List<JobFile>> _mergeWithRemote({
    required String jobId,
    required JobFileType fileType,
    required List<JobFile> local,
  }) async {
    List<JobFile> remote = const <JobFile>[];
    try {
      remote = await _filesRemote.getJobFilesByType(jobId, fileType.name);
    } catch (error, stackTrace) {
      // Offline (or unauthorized): the local photos remain the answer — but
      // the reason is logged, never silently swallowed.
      AppLogger.warning(
        'Remote job files could not be merged for job $jobId '
        '(${fileType.name}); using local rows only.',
        error: error,
        stackTrace: stackTrace,
      );
    }

    final Set<String> localIds = local.map((JobFile file) => file.id).toSet();
    final List<JobFile> merged = <JobFile>[
      ...local,
      ...remote.where((JobFile file) => !localIds.contains(file.id)),
    ];
    merged.sort((JobFile a, JobFile b) => a.capturedAt.compareTo(b.capturedAt));
    return merged;
  }

  /// Maps a picked file's extension to a MIME type (image/jpeg fallback).
  String? _mimeTypeFor(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.heic':
      case '.heif':
        return 'image/heic';
      case '.jpg':
      case '.jpeg':
      case '':
        return 'image/jpeg';
      default:
        return null;
    }
  }
}
