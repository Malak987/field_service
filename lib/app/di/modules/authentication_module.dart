import 'package:field_service/features/authentication/data/datasources/authentication_remote_data_source.dart';
import 'package:field_service/features/authentication/data/repositories/authentication_repository_impl.dart';
import 'package:field_service/features/authentication/domain/repositories/authentication_repository.dart';
import 'package:field_service/features/authentication/domain/usecases/get_current_user.dart';
import 'package:field_service/features/authentication/domain/usecases/sign_in.dart';
import 'package:field_service/features/authentication/domain/usecases/sign_out.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';

void registerAuthenticationModule(GetIt sl) {
  sl.registerLazySingleton<AuthenticationRemoteDataSource>(
        () => AuthenticationRemoteDataSourceImpl(
      sl<SupabaseClient>(),
    ),
  );

  sl.registerLazySingleton<AuthenticationRepository>(
        () => AuthenticationRepositoryImpl(
      remoteDataSource: sl<AuthenticationRemoteDataSource>(),
      supabase: sl<SupabaseClient>(),
    ),
  );

  sl.registerLazySingleton<SignIn>(
        () => SignIn(sl<AuthenticationRepository>()),
  );

  sl.registerLazySingleton<SignOut>(
        () => SignOut(sl<AuthenticationRepository>()),
  );

  sl.registerLazySingleton<GetCurrentUser>(
        () => GetCurrentUser(sl<AuthenticationRepository>()),
  );
  sl.registerFactory<AuthenticationCubit>(
        () => AuthenticationCubit(
      signIn: sl<SignIn>(),
      signOut: sl<SignOut>(),
      getCurrentUser: sl<GetCurrentUser>(),
    ),
  );
}