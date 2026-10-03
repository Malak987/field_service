import 'package:equatable/equatable.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';

enum AuthenticationStatus {
  initial,
  loading,
  authenticated,
  unauthenticated,
  failure,
}

class AuthenticationState extends Equatable {
  const AuthenticationState({
    this.status = AuthenticationStatus.initial,
    this.user,
    this.message,
  });

  final AuthenticationStatus status;
  final AppUser? user;
  final String? message;

  AuthenticationState copyWith({
    AuthenticationStatus? status,
    AppUser? user,
    String? message,
    bool clearUser = false,
    bool clearMessage = false,
  }) {
    return AuthenticationState(
      status: status ?? this.status,
      user: clearUser ? null : user ?? this.user,
      message: clearMessage ? null : message ?? this.message,
    );
  }

  @override
  List<Object?> get props => [
    status,
    user,
    message,
  ];
}