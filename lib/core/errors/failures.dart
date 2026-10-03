import 'package:field_service/core/errors/failure.dart';

/// The backend was reached and refused or failed the operation.
///
/// Typical sources: rejected write during a sync push, validation refusal,
/// server-side error on a pull.
final class ServerFailure extends Failure {
  const ServerFailure({required super.message, super.code, super.cause});

  @override
  FailureType get type => FailureType.server;
}

/// The device has no usable internet connection.
///
/// This is an expected outcome in the field, not a crash: local writes are
/// queued for the sync engine instead of being reported as an error.
final class NetworkFailure extends Failure {
  const NetworkFailure({required super.message, super.code, super.cause});

  @override
  FailureType get type => FailureType.network;
}

/// Local persistence failed (Drift/SQLite, cached payloads, preferences).
final class CacheFailure extends Failure {
  const CacheFailure({required super.message, super.code, super.cause});

  @override
  FailureType get type => FailureType.cache;
}

/// The session is missing, expired or was rejected by the backend.
///
/// Presentation reacts by sending the user back to the login route; the
/// redirect logic itself belongs to the authentication phase.
final class AuthenticationFailure extends Failure {
  const AuthenticationFailure({
    required super.message,
    super.code,
    super.cause,
  });

  @override
  FailureType get type => FailureType.authentication;
}

/// Reading or writing a file on the device failed.
///
/// Relevant for job files (before/after photos, customer signatures) and for
/// exports; the bytes are never stored in the database.
final class StorageFailure extends Failure {
  const StorageFailure({required super.message, super.code, super.cause});

  @override
  FailureType get type => FailureType.storage;
}

/// A problem that was not anticipated.
///
/// Mapped from any unexpected exception so the presentation layer always has a
/// failure to show, and so unmapped cases are greppable (and reportable) rather
/// than silently swallowed.
final class UnexpectedFailure extends Failure {
  const UnexpectedFailure({required super.message, super.code, super.cause});

  @override
  FailureType get type => FailureType.unexpected;
}
