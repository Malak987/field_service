import 'package:field_service/core/storage/file_storage.dart';
import 'package:field_service/core/storage/local_file_storage.dart';
import 'package:field_service/core/sync/sync_handler.dart';
import 'package:field_service/core/sync/sync_operation.dart';
import 'package:field_service/features/jobs/data/datasources/job_files_remote_data_source.dart';
import 'package:field_service/features/jobs/data/datasources/jobs_remote_data_source.dart';
import 'package:field_service/features/jobs/data/repositories/jobs_repository_impl.dart';
import 'package:field_service/features/jobs/data/sync/job_file_sync_handler.dart';
import 'package:field_service/features/jobs/data/sync/job_sync_handler.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';
import 'package:field_service/features/jobs/domain/usecases/add_before_photo.dart';
import 'package:field_service/features/jobs/domain/usecases/get_failed_job_file_ids.dart';
import 'package:field_service/features/jobs/domain/usecases/get_job_by_id.dart';
import 'package:field_service/features/jobs/domain/usecases/get_job_customer_info.dart';
import 'package:field_service/features/jobs/domain/usecases/get_before_photos.dart';
import 'package:field_service/features/jobs/domain/usecases/get_jobs.dart';
import 'package:field_service/features/jobs/domain/usecases/read_job_file_bytes.dart';
import 'package:field_service/features/jobs/domain/usecases/retry_failed_syncs.dart';
import 'package:field_service/features/jobs/domain/usecases/start_job.dart';
import 'package:field_service/features/jobs/domain/usecases/update_job_status.dart';
import 'package:field_service/features/jobs/domain/usecases/watch_before_photos.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_cubit.dart';
import 'package:field_service/features/jobs/presentation/services/photo_picker.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Composition root of the Jobs feature.
///
/// Follows the same layering as the authentication module:
/// data source (Supabase) → repository (domain contract) → use cases → cubit,
/// plus the offline-first write integration used by the Customers feature:
/// the repository receives the shared sync queue/processor, and this
/// feature's [SyncOperationHandler]s register into the shared registry (the
/// one integration point — the `SyncManager` needs no knowledge of jobs).
///
/// Before Photos reuses the existing offline stack end to end:
/// `LocalFileStorage` (app-owned storage + local `job_files` rows + durable
/// queue entries) → [JobFileSyncHandler] (Storage upload + `register_job_file`
/// RPC) — no second queue, no second storage abstraction.
void registerJobsModule(GetIt sl) {
  sl.registerLazySingleton<JobsRemoteDataSource>(
    () => JobsRemoteDataSourceImpl(
      sl<SupabaseClient>(),
    ),
  );

  sl.registerLazySingleton<JobFilesRemoteDataSource>(
    () => JobFilesRemoteDataSourceImpl(
      sl<SupabaseClient>(),
    ),
  );

  sl.registerLazySingleton<JobsRepository>(
    () => JobsRepositoryImpl(
      remoteDataSource: sl<JobsRemoteDataSource>(),
      syncQueue: sl(),
      syncProcessor: sl(),
      localFileStorage: sl<LocalFileStorage>(),
      fileStorage: sl<FileStorage>(),
      filesRemoteDataSource: sl<JobFilesRemoteDataSource>(),
    ),
  );

  sl.registerLazySingleton<GetJobs>(
    () => GetJobs(sl<JobsRepository>()),
  );

  sl.registerLazySingleton<GetJobById>(
    () => GetJobById(sl<JobsRepository>()),
  );

  sl.registerLazySingleton<GetJobCustomerInfo>(
    () => GetJobCustomerInfo(sl<JobsRepository>()),
  );

  sl.registerLazySingleton<UpdateJobStatus>(
    () => UpdateJobStatus(sl<JobsRepository>()),
  );

  sl.registerLazySingleton<StartJob>(
    () => StartJob(sl<JobsRepository>()),
  );

  // --- Before Photos use cases ------------------------------------------------
  sl.registerLazySingleton<AddBeforePhoto>(
    () => AddBeforePhoto(sl<JobsRepository>()),
  );

  sl.registerLazySingleton<GetBeforePhotos>(
    () => GetBeforePhotos(sl<JobsRepository>()),
  );

  sl.registerLazySingleton<WatchBeforePhotos>(
    () => WatchBeforePhotos(sl<JobsRepository>()),
  );

  sl.registerLazySingleton<ReadJobFileBytes>(
    () => ReadJobFileBytes(sl<JobsRepository>()),
  );

  sl.registerLazySingleton<RetryFailedSyncs>(
    () => RetryFailedSyncs(sl<JobsRepository>()),
  );

  sl.registerLazySingleton<GetFailedJobFileIds>(
    () => GetFailedJobFileIds(sl<JobsRepository>()),
  );

  // Camera/gallery access (wraps the existing image_picker dependency).
  sl.registerLazySingleton<PhotoPicker>(
    () => ImagePickerPhotoPicker(),
  );

  sl.registerFactory<JobsCubit>(
    () => JobsCubit(
      getJobs: sl<GetJobs>(),
      getJobById: sl<GetJobById>(),
      getJobCustomerInfo: sl<GetJobCustomerInfo>(),
      updateJobStatus: sl<UpdateJobStatus>(),
      startJob: sl<StartJob>(),
      addBeforePhoto: sl<AddBeforePhoto>(),
      watchBeforePhotos: sl<WatchBeforePhotos>(),
      readJobFileBytes: sl<ReadJobFileBytes>(),
      retryFailedSyncs: sl<RetryFailedSyncs>(),
      getFailedJobFileIds: sl<GetFailedJobFileIds>(),
    ),
  );

  // --- Sync integration -----------------------------------------------------
  sl.registerLazySingleton<JobSyncHandler>(
    () => JobSyncHandler(remote: sl<JobsRemoteDataSource>()),
  );

  sl<MutableSyncHandlerRegistry>().registerFactory(
    SyncEntityType.job,
    () => sl<JobSyncHandler>(),
  );

  sl.registerLazySingleton<JobFileSyncHandler>(
    () => JobFileSyncHandler(
      localFiles: sl<LocalFileStorage>(),
      fileStorage: sl<FileStorage>(),
      remote: sl<JobFilesRemoteDataSource>(),
    ),
  );

  sl<MutableSyncHandlerRegistry>().registerFactory(
    SyncEntityType.jobFile,
    () => sl<JobFileSyncHandler>(),
  );
}
