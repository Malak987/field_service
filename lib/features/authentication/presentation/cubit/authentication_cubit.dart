import 'package:field_service/features/authentication/domain/usecases/get_current_user.dart';
import 'package:field_service/features/authentication/domain/usecases/sign_in.dart';
import 'package:field_service/features/authentication/domain/usecases/sign_out.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AuthenticationCubit extends Cubit<AuthenticationState> {
  AuthenticationCubit({
    required this._signIn,
    required this._signOut,
    required this._getCurrentUser,
  }) : super(const AuthenticationState());

  final SignIn _signIn;
  final SignOut _signOut;
  final GetCurrentUser _getCurrentUser;

  Future<void> checkCurrentUser() async {
    emit(
      state.copyWith(
        status: AuthenticationStatus.loading,
        clearMessage: true,
      ),
    );

    try {
      final user = await _getCurrentUser();

      if (user == null) {
        emit(
          state.copyWith(
            status: AuthenticationStatus.unauthenticated,
            clearUser: true,
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          status: AuthenticationStatus.authenticated,
          user: user,
          clearMessage: true,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: AuthenticationStatus.failure,
          message: error.toString(),
          clearUser: true,
        ),
      );
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    emit(
      state.copyWith(
        status: AuthenticationStatus.loading,
        clearMessage: true,
      ),
    );

    try {
      final user = await _signIn(
        email: email,
        password: password,
      );

      emit(
        state.copyWith(
          status: AuthenticationStatus.authenticated,
          user: user,
          clearMessage: true,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: AuthenticationStatus.failure,
          message: error.toString(),
          clearUser: true,
        ),
      );
    }
  }

  Future<void> signOut() async {
    emit(
      state.copyWith(
        status: AuthenticationStatus.loading,
        clearMessage: true,
      ),
    );

    try {
      await _signOut();

      emit(
        state.copyWith(
          status: AuthenticationStatus.unauthenticated,
          clearUser: true,
          clearMessage: true,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: AuthenticationStatus.failure,
          message: error.toString(),
        ),
      );
    }
  }
}