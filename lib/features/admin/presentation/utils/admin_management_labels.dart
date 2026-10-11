import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/features/admin/domain/entities/admin_account_status.dart';

/// Localized label of an [AdminAccountStatus] (English + German through the
/// existing [AppLocalizations] system — no hardcoded UI strings).
String adminStatusLabel(AppLocalizations l10n, AdminAccountStatus status) {
  switch (status) {
    case AdminAccountStatus.active:
      return l10n.adminStatusActive;
    case AdminAccountStatus.blocked:
      return l10n.adminStatusBlocked;
    case AdminAccountStatus.deleted:
      return l10n.adminStatusDeleted;
    case AdminAccountStatus.unknown:
      return l10n.adminStatusUnknown;
  }
}

/// Localized, user-facing explanation of a failed management action.
///
/// The nuance matters to the admin: "not authorized" (the account lost its
/// admin rights), "deleted record" (a soft deleted account cannot be
/// reactivated) and "blocked customer" (no new job for that customer) are
/// different situations with different next steps.
String adminFailureMessage(AppLocalizations l10n, AdminFailureKind kind) {
  switch (kind) {
    case AdminFailureKind.notAuthorized:
      return l10n.adminErrorNotAuthorized;
    case AdminFailureKind.notFound:
      return l10n.adminErrorNotFound;
    case AdminFailureKind.recordDeleted:
      return l10n.adminErrorRecordDeleted;
    case AdminFailureKind.invalidInput:
      return l10n.adminErrorInvalidInput;
    case AdminFailureKind.customerBlocked:
      return l10n.adminErrorCustomerBlocked;
    case AdminFailureKind.network:
      return l10n.adminErrorNetwork;
    case AdminFailureKind.unknown:
      return l10n.adminErrorUnknown;
  }
}
