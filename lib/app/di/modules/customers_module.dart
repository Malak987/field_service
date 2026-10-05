import 'package:field_service/core/sync/sync_handler.dart';
import 'package:field_service/core/sync/sync_operation.dart';
import 'package:field_service/features/customers/data/datasources/customers_local_data_source.dart';
import 'package:field_service/features/customers/data/datasources/customers_remote_data_source.dart';
import 'package:field_service/features/customers/data/repositories/customers_repository_impl.dart';
import 'package:field_service/features/customers/data/sync/customer_sync_handler.dart';
import 'package:field_service/features/customers/domain/repositories/customers_repository.dart';
import 'package:field_service/features/customers/domain/usecases/create_customer.dart';
import 'package:field_service/features/customers/domain/usecases/delete_customer.dart';
import 'package:field_service/features/customers/domain/usecases/get_customer_by_id.dart';
import 'package:field_service/features/customers/domain/usecases/get_customers.dart';
import 'package:field_service/features/customers/domain/usecases/refresh_customers.dart';
import 'package:field_service/features/customers/domain/usecases/update_customer.dart';
import 'package:field_service/features/customers/presentation/cubit/customers_cubit.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Composition root of the Customers feature.
///
/// Same layering as the Jobs module — data sources → repository → use
/// cases → cubit — plus the offline-first additions: the Drift-backed local
/// data source, the shared sync queue wiring, and this feature's
/// [SyncOperationHandler] registered into the shared registry (the one
/// integration point, so the `SyncManager` needs no knowledge of customers).
void registerCustomersModule(GetIt sl) {
  // --- Data sources -----------------------------------------------------------
  // Local: the offline-first source of truth (Drift mirror).
  // Remote: raw Supabase access, only reached by sync/pull code paths.
  sl.registerLazySingleton<CustomersLocalDataSource>(
    () => DriftCustomersLocalDataSource(sl()),
  );

  sl.registerLazySingleton<CustomersRemoteDataSource>(
    () => CustomersRemoteDataSourceImpl(sl<SupabaseClient>()),
  );

  // --- Repository --------------------------------------------------------------
  sl.registerLazySingleton<CustomersRepository>(
    () => CustomersRepositoryImpl(
      local: sl<CustomersLocalDataSource>(),
      remote: sl<CustomersRemoteDataSource>(),
      syncQueue: sl(),
      syncProcessor: sl(),
      connectivity: sl(),
    ),
  );

  // --- Use cases ---------------------------------------------------------------
  sl.registerLazySingleton<GetCustomers>(
    () => GetCustomers(sl<CustomersRepository>()),
  );

  sl.registerLazySingleton<GetCustomerById>(
    () => GetCustomerById(sl<CustomersRepository>()),
  );

  sl.registerLazySingleton<CreateCustomer>(
    () => CreateCustomer(sl<CustomersRepository>()),
  );

  sl.registerLazySingleton<UpdateCustomer>(
    () => UpdateCustomer(sl<CustomersRepository>()),
  );

  sl.registerLazySingleton<DeleteCustomer>(
    () => DeleteCustomer(sl<CustomersRepository>()),
  );

  sl.registerLazySingleton<RefreshCustomers>(
    () => RefreshCustomers(sl<CustomersRepository>()),
  );

  // --- Presentation ------------------------------------------------------------
  // Factory: the list page and each details page own one cubit instance.
  sl.registerFactory<CustomersCubit>(
    () => CustomersCubit(
      getCustomers: sl<GetCustomers>(),
      getCustomerById: sl<GetCustomerById>(),
      createCustomer: sl<CreateCustomer>(),
      updateCustomer: sl<UpdateCustomer>(),
      deleteCustomer: sl<DeleteCustomer>(),
      refreshCustomers: sl<RefreshCustomers>(),
    ),
  );

  // --- Sync integration ----------------------------------------------------------
  sl.registerLazySingleton<CustomerSyncHandler>(
    () => CustomerSyncHandler(
      remote: sl<CustomersRemoteDataSource>(),
      local: sl<CustomersLocalDataSource>(),
    ),
  );

  sl<MutableSyncHandlerRegistry>().register(
    SyncEntityType.customer,
    sl<CustomerSyncHandler>(),
  );
}
