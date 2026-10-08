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
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
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
