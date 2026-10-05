import 'package:field_service/features/authentication/data/datasources/authentication_remote_data_source.dart';
import 'package:field_service/features/authentication/data/repositories/authentication_repository_impl.dart';
import 'package:field_service/features/authentication/domain/repositories/authentication_repository.dart';
import 'package:field_service/features/authentication/domain/usecases/get_current_user.dart';
import 'package:field_service/features/authentication/domain/usecases/send_password_reset_email.dart';
import 'package:field_service/features/authentication/domain/usecases/sign_in.dart';
import 'package:field_service/features/authentication/domain/usecases/sign_out.dart';
import 'package:field_service/features/authentication/domain/usecases/sign_up.dart';
import 'package:field_service/features/authentication/domain/usecases/update_password.dart';
import 'package:field_service/features/authentication/domain/usecases/watch_auth_state_changes.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void registerAuthenticationModule(GetIt sl) {
  sl.registerLazySingleton<AuthenticationRemoteDataSource>(
    () => AuthenticationRemoteDataSourceImpl(sl<SupabaseClient>()),
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

  sl.registerLazySingleton<SignUp>(
    () => SignUp(sl<AuthenticationRepository>()),
  );

  sl.registerLazySingleton<SendPasswordResetEmail>(
    () => SendPasswordResetEmail(sl<AuthenticationRepository>()),
  );

  sl.registerLazySingleton<UpdatePassword>(
    () => UpdatePassword(sl<AuthenticationRepository>()),
  );

  sl.registerLazySingleton<SignOut>(
    () => SignOut(sl<AuthenticationRepository>()),
  );

  sl.registerLazySingleton<GetCurrentUser>(
    () => GetCurrentUser(sl<AuthenticationRepository>()),
  );

  sl.registerLazySingleton<WatchAuthStateChanges>(
    () => WatchAuthStateChanges(sl<AuthenticationRepository>()),
  );

  // One session owner for the gate, router and all feature/authentication pages.
  sl.registerLazySingleton<AuthenticationCubit>(
    () => AuthenticationCubit(
      signIn: sl<SignIn>(),
      signUp: sl<SignUp>(),
      sendPasswordResetEmail: sl<SendPasswordResetEmail>(),
      updatePassword: sl<UpdatePassword>(),
      signOut: sl<SignOut>(),
      getCurrentUser: sl<GetCurrentUser>(),
      watchAuthStateChanges: sl<WatchAuthStateChanges>(),
    ),
    dispose: (AuthenticationCubit cubit) => cubit.close(),
  );
}
