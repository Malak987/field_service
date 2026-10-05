import 'package:field_service/features/jobs/data/datasources/jobs_remote_data_source.dart';
import 'package:field_service/features/jobs/data/repositories/jobs_repository_impl.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';
import 'package:field_service/features/jobs/domain/usecases/get_job_by_id.dart';
import 'package:field_service/features/jobs/domain/usecases/get_jobs.dart';
import 'package:field_service/features/jobs/domain/usecases/update_job_status.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_cubit.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Composition root of the Jobs feature.
///
/// Follows the same layering as the authentication module:
/// data source (Supabase) → repository (domain contract) → use cases → cubit.
void registerJobsModule(GetIt sl) {
  sl.registerLazySingleton<JobsRemoteDataSource>(
    () => JobsRemoteDataSourceImpl(
      sl<SupabaseClient>(),
    ),
  );

  sl.registerLazySingleton<JobsRepository>(
    () => JobsRepositoryImpl(
      remoteDataSource: sl<JobsRemoteDataSource>(),
    ),
  );

  sl.registerLazySingleton<GetJobs>(
    () => GetJobs(sl<JobsRepository>()),
  );

  sl.registerLazySingleton<GetJobById>(
    () => GetJobById(sl<JobsRepository>()),
  );

  sl.registerLazySingleton<UpdateJobStatus>(
    () => UpdateJobStatus(sl<JobsRepository>()),
  );

  sl.registerFactory<JobsCubit>(
    () => JobsCubit(
      getJobs: sl<GetJobs>(),
      getJobById: sl<GetJobById>(),
      updateJobStatus: sl<UpdateJobStatus>(),
    ),
  );
}
