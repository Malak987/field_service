/// Failure categories the account-deletion UI can explain safely.
enum AccountDeletionFailureKind {
  sessionInvalid,
  lastActiveAdmin,
  requestFailed,
}

/// A sanitized failure from the backend-owned deletion workflow.
///
/// [status], [reasonPhrase], and [details] preserve diagnostics from a
/// Supabase Function response for application logging. They are sanitized
/// before this type is constructed and are never rendered to an end user.
class AccountDeletionFailure implements Exception {
  const AccountDeletionFailure(
    this.kind, {
    this.status,
    this.reasonPhrase,
    this.details,
  });

  final AccountDeletionFailureKind kind;
  final int? status;
  final String? reasonPhrase;
  final String? details;

  @override
  String toString() =>
      'AccountDeletionFailure('
      'kind: $kind, '
      'status: ${status ?? 'unknown'}, '
      'reasonPhrase: ${reasonPhrase ?? 'none'}, '
      'details: ${details ?? 'none'}'
      ')';
}
