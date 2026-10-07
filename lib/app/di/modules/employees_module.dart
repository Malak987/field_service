import 'package:field_service/features/employees/data/datasources/employees_remote_data_source.dart';
import 'package:field_service/features/employees/data/repositories/employees_repository_impl.dart';
import 'package:field_service/features/employees/domain/repositories/employees_repository.dart';
import 'package:field_service/features/employees/domain/usecases/get_active_technicians.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Composition root of the Employees feature.
///
/// Same layering as the other features: data source (Supabase) → repository
/// (domain contract) → use case. The surface is deliberately narrow — the
/// app needs exactly one read (the assignee options of the admin Create Job
/// screen); every authorization decision stays server-side (employees RLS +
/// the `create_job` RPC).
void registerEmployeesModule(GetIt sl) {
  sl.registerLazySingleton<EmployeesRemoteDataSource>(
    () => EmployeesRemoteDataSourceImpl(sl<SupabaseClient>()),
  );

  sl.registerLazySingleton<EmployeesRepository>(
    () => EmployeesRepositoryImpl(sl<EmployeesRemoteDataSource>()),
  );

  sl.registerLazySingleton<GetActiveTechnicians>(
    () => GetActiveTechnicians(sl<EmployeesRepository>()),
  );
}
