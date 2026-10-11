/// Lifecycle state of an admin-managed account (technician or customer).
///
/// The values mirror the database state machine of
/// `supabase/admin_management_setup.sql` — `public.employees.account_status`
/// and `public.customers.account_status`:
///
/// | status    | meaning                                                        |
/// |-----------|----------------------------------------------------------------|
/// | `active`  | usable: signs in, executes jobs / can be assigned to a job      |
/// | `blocked` | deactivated server-side — cannot execute anything, cannot be     |
/// |           | chosen for a NEW job, old records stay readable                 |
/// | `deleted` | soft deleted — the row (and all its history) stays in the        |
/// |           | database, but the account is out of every operational path       |
/// | `unknown` | the value the server sent is not one of the three known states   |
/// |           | (defensive: the UI must never crash on new server values)        |
enum AdminAccountStatus {
  active,
  blocked,
  deleted,
  unknown;

  /// Maps the raw `account_status` column value.
  ///
  /// [isActive] is the legacy `employees.is_active` flag used as a fallback
  /// for rows written before the lifecycle columns existed.
  static AdminAccountStatus fromRemote(String? raw, {bool? isActive}) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'active':
        return AdminAccountStatus.active;
      case 'blocked':
        return AdminAccountStatus.blocked;
      case 'deleted':
        return AdminAccountStatus.deleted;
      case '':
        // No status column value: derive it from the legacy flag.
        if (isActive == null) {
          return AdminAccountStatus.unknown;
        }
        return isActive ? AdminAccountStatus.active : AdminAccountStatus.blocked;
      default:
        return AdminAccountStatus.unknown;
    }
  }

  /// The value sent to the management RPCs.
  String get remoteValue => switch (this) {
    AdminAccountStatus.active => 'active',
    AdminAccountStatus.blocked => 'blocked',
    AdminAccountStatus.deleted => 'deleted',
    AdminAccountStatus.unknown => 'unknown',
  };

  bool get isActive => this == AdminAccountStatus.active;
  bool get isBlocked => this == AdminAccountStatus.blocked;
  bool get isDeleted => this == AdminAccountStatus.deleted;
}

/// The typed reason a management action failed, produced by the data layer
/// (see `AdminFailure`) and rendered as a localized message by the UI.
///
/// Keeping the *kind* instead of a raw exception in the presentation state
/// means the pages never touch Supabase/PostgREST types and every message is
/// translated.
enum AdminFailureKind {
  /// The server refused the caller (SQLSTATE 42501) — not an active admin.
  notAuthorized,

  /// The record does not exist (SQLSTATE P0002).
  notFound,

  /// The record is soft deleted: it cannot be edited, reactivated or re-blocked.
  recordDeleted,

  /// The submitted data was refused (empty name/address, unsupported status).
  invalidInput,

  /// A blocked/deleted customer can never be attached to a new job (F0008).
  customerBlocked,

  /// The request never reached the server (offline / network error).
  network,

  /// Anything else — logged with its cause, shown as a generic message.
  unknown,
}
