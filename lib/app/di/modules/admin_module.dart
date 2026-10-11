import 'package:field_service/features/admin/data/datasources/admin_remote_data_source.dart';
import 'package:field_service/features/admin/data/repositories/admin_repository_impl.dart';
import 'package:field_service/features/admin/domain/repositories/admin_repository.dart';
import 'package:field_service/features/admin/domain/usecases/create_managed_customer.dart';
import 'package:field_service/features/admin/domain/usecases/get_unavailable_customer_ids.dart';
import 'package:field_service/features/admin/domain/usecases/list_managed_customers.dart';
import 'package:field_service/features/admin/domain/usecases/list_managed_employees.dart';
import 'package:field_service/features/admin/domain/usecases/set_customer_status.dart';
import 'package:field_service/features/admin/domain/usecases/set_employee_status.dart';
import 'package:field_service/features/admin/domain/usecases/update_managed_customer.dart';
import 'package:field_service/features/admin/presentation/cubit/admin_customers_cubit.dart';
import 'package:field_service/features/admin/presentation/cubit/technicians_cubit.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Composition root of the Admin management feature (technicians + customers).
///
/// Same layering as the other features — data source (Supabase RPCs) →
/// repository (domain contract) → use cases → cubits. The RPCs themselves are
/// admin-only SECURITY DEFINER functions, so the graph carries no
/// authorization logic: the server decides, the UI only presents.
void registerAdminModule(GetIt sl) {
  // --- Data source ------------------------------------------------------------
  sl.registerLazySingleton<AdminRemoteDataSource>(
    () => AdminRemoteDataSourceImpl(sl<SupabaseClient>()),
  );

  // --- Repository --------------------------------------------------------------
  sl.registerLazySingleton<AdminRepository>(
    () => AdminRepositoryImpl(sl<AdminRemoteDataSource>()),
  );

  // --- Use cases ---------------------------------------------------------------
  sl.registerLazySingleton<ListManagedEmployees>(
    () => ListManagedEmployees(sl<AdminRepository>()),
  );

  sl.registerLazySingleton<SetEmployeeStatus>(
    () => SetEmployeeStatus(sl<AdminRepository>()),
  );

  sl.registerLazySingleton<ListManagedCustomers>(
    () => ListManagedCustomers(sl<AdminRepository>()),
  );

  sl.registerLazySingleton<CreateManagedCustomer>(
    () => CreateManagedCustomer(sl<AdminRepository>()),
  );

  sl.registerLazySingleton<UpdateManagedCustomer>(
    () => UpdateManagedCustomer(sl<AdminRepository>()),
  );

  sl.registerLazySingleton<SetCustomerStatus>(
    () => SetCustomerStatus(sl<AdminRepository>()),
  );

  // Consumed by the admin Create Job screen to keep blocked/deleted customers
  // out of the selector (the `create_job` RPC refuses them regardless).
  sl.registerLazySingleton<GetUnavailableCustomerIds>(
    () => GetUnavailableCustomerIds(sl<AdminRepository>()),
  );

  // --- Presentation -------------------------------------------------------------
  // Factory: each management page owns one cubit instance.
  sl.registerFactory<TechniciansCubit>(
    () => TechniciansCubit(
      listManagedEmployees: sl<ListManagedEmployees>(),
      setEmployeeStatus: sl<SetEmployeeStatus>(),
    ),
  );

  sl.registerFactory<AdminCustomersCubit>(
    () => AdminCustomersCubit(
      listManagedCustomers: sl<ListManagedCustomers>(),
      createManagedCustomer: sl<CreateManagedCustomer>(),
      updateManagedCustomer: sl<UpdateManagedCustomer>(),
      setCustomerStatus: sl<SetCustomerStatus>(),
    ),
  );
}
