import 'package:field_service/features/admin/domain/entities/admin_account_status.dart';

/// Domain-level failure of an admin management operation.
///
/// The data layer converts the transport exception (PostgREST/SQLSTATE, socket
/// errors) into this single type, so the presentation layer never imports
/// `supabase_flutter` and every failure can be translated.
///
/// [code] keeps the raw SQLSTATE/PostgREST code for logs and for tests; [message]
/// keeps the server message (also used to distinguish the "deleted record"
/// family, which the database reports as `P0001`).
class AdminFailure implements Exception {
  const AdminFailure(this.kind, {this.code, this.message});

  /// What went wrong, in presentation terms.
  final AdminFailureKind kind;

  /// Raw code of the underlying error (e.g. `42501`, `P0001`, `F0008`).
  final String? code;

  /// Raw message of the underlying error — never shown to the user directly.
  final String? message;

  @override
  String toString() => 'AdminFailure(${kind.name}, code: $code, message: $message)';
}
