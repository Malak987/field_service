import 'package:equatable/equatable.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/presentation/utils/authentication_error_mapper.dart';

enum AuthenticationStatus {
  initial,
  loading,
  authenticated,
  unauthenticated,
  failure,
  passwordRecovery,
  passwordResetEmailSent,
  passwordResetSuccess,
  registrationSuccess,
}

class AuthenticationState extends Equatable {
  const AuthenticationState({
    this.status = AuthenticationStatus.initial,
    this.user,
    this.errorCode,
    this.message,
  });

  final AuthenticationStatus status;
  final AppUser? user;
  final AuthErrorCode? errorCode;
  final String? message;

  bool get isLoading => status == AuthenticationStatus.loading;

  bool get isAuthenticated =>
      status == AuthenticationStatus.authenticated && user != null;

  bool get hasError =>
      status == AuthenticationStatus.failure &&
      (errorCode != null || (message != null && message!.isNotEmpty));

  AuthenticationState copyWith({
    AuthenticationStatus? status,
    AppUser? user,
    AuthErrorCode? errorCode,
    String? message,
    bool clearUser = false,
    bool clearErrorCode = false,
    bool clearMessage = false,
  }) {
    return AuthenticationState(
      status: status ?? this.status,
      user: clearUser ? null : user ?? this.user,
      errorCode: clearErrorCode ? null : errorCode ?? this.errorCode,
      message: clearMessage ? null : message ?? this.message,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    user,
    errorCode,
    message,
  ];
}
