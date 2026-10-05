import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/utils/password_validator.dart';

/// Centralized, reusable validation for the customer form.
///
/// Mirrors `PasswordValidator`'s role for the auth forms: every customer
/// page (create, edit) consumes these static rules instead of owning form
/// logic, and the messages come exclusively from [AppLocalizations].
abstract final class CustomerFormValidators {
  /// Required free-text field (name, address).
  static String? validateRequired(String? value, AppLocalizations l10n) {
    if (value == null || value.trim().isEmpty) {
      return l10n.validationRequiredField;
    }
    return null;
  }

  /// Optional email field: blank is valid; anything else must parse.
  ///
  /// The actual syntax check reuses the single project-wide email rule in
  /// [PasswordValidator] — no second regex anywhere.
  static String? validateOptionalEmail(String? value, AppLocalizations l10n) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    return PasswordValidator.validateEmail(trimmed, l10n);
  }
}
