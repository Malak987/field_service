import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';
import 'package:flutter/material.dart';

/// Maps a technician job-creation failure onto a localized, user-safe
/// message.
///
/// Same role as `AuthenticationErrorMapper`: the server's own text is a
/// diagnostic (logged by the repository), never shown verbatim — the
/// technician gets one of the app's translated explanations instead.
abstract final class TechnicianJobErrorMapper {
  /// The message to show for [error] (`null` → the generic failure text).
  static String messageFor(Object? error, BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    if (error is TechnicianJobCreationRejectedException) {
      return switch (error.reason) {
        TechnicianJobRejectReason.unauthorized =>
          l10n.technicianCreateJobErrorUnauthorized,
        TechnicianJobRejectReason.customerNotFound =>
          l10n.technicianCreateJobErrorCustomerNotFound,
        TechnicianJobRejectReason.customerBlocked =>
          l10n.technicianCreateJobErrorCustomerBlocked,
        TechnicianJobRejectReason.invalidInput =>
          l10n.technicianCreateJobErrorInvalidInput,
        TechnicianJobRejectReason.notAuthenticated =>
          l10n.technicianCreateJobErrorNotAuthenticated,
        TechnicianJobRejectReason.unknown =>
          l10n.technicianCreateJobErrorUnknown,
      };
    }

    if (error is ArgumentError) {
      // A client-side pre-flight refusal (unsupported category, over-length
      // field): the form itself is the thing to fix.
      return l10n.technicianCreateJobErrorInvalidInput;
    }

    return l10n.technicianCreateJobFailed;
  }
}
