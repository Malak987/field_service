import 'package:equatable/equatable.dart';

/// The kind of a [Failure].
///
/// It carries two responsibilities:
/// * it is part of [Failure.props], so two failures of different kinds are
///   never considered equal even when their messages match;
/// * it lets presentation react to a failure (`switch` on the kind to pick an
///   icon, decide whether "retry" is offered) without depending on the concrete
///   classes of the data layer.
enum FailureType {
  /// The backend was reached but answered with an error.
  server,

  /// The device has no usable internet connection.
  network,

  /// Local persistence failed (database, cached payloads, preferences).
  cache,

  /// Session/token missing, expired or rejected.
  authentication,

  /// Reading or writing a file on the device failed.
  storage,

  /// Anything that was not anticipated. Always logged, never silent.
  unexpected,
}

/// Base type for every expected, recoverable error of the application.
///
/// A [Failure] is what a repository returns and a use case forwards to the
/// presentation layer; its data-layer counterpart is an exception, which is
/// raised while talking to a backend, a database or the file system and then
/// translated into a failure at the repository boundary.
///
/// It is deliberately pure Dart — no Flutter, Supabase, Drift or HTTP type may
/// ever appear in this file — so the Domain layer stays framework independent
/// and fully unit-testable.
///
/// Keep it small: this hierarchy describes *what kind* of problem happened in a
/// way the UI can present. Retry policies, error codes and telemetry belong to
/// the sync/observability phases.
abstract class Failure extends Equatable {
  const Failure({required this.message, this.code, this.cause});

  /// Safe, user-presentable message. Never a raw exception string.
  final String message;

  /// Optional machine readable code (HTTP status, database error code, ...).
  final String? code;

  /// The original error, kept for logging and diagnostics.
  ///
  /// It is deliberately excluded from [props]: two failures are the same
  /// failure when their kind, message and code match, regardless of the
  /// identity of the underlying object (which is often not comparable).
  final Object? cause;

  /// The concrete kind of this failure.
  FailureType get type;

  @override
  List<Object?> get props => <Object?>[type, message, code];

  @override
  String toString() {
    final String codeSuffix = code == null ? '' : ', code: $code';
    return '$runtimeType(message: $message$codeSuffix)';
  }
}
