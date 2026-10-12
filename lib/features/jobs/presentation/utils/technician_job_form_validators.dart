import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/features/customers/presentation/utils/customer_form_validators.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Validation rules of the technician's "Create Customer & Job" form.
///
/// Pure Dart and dependency-free, exactly like [CustomerFormValidators] and
/// `PasswordValidator`: every message comes from [AppLocalizations], so the
/// rules are unit-testable without a widget tree and localized for free.
///
/// The email rule is NOT duplicated here — it delegates to the single
/// project-wide rule in [CustomerFormValidators]. The phone rule is new:
/// the project had none before (the admin customer form accepts any text),
/// and it is deliberately conservative so a technician on site is never
/// blocked by a formatting opinion — only by something that cannot be a
/// phone number at all.
abstract final class TechnicianJobFormValidators {
  /// Characters a phone number may contain (digits, spaces and the usual
  /// separators). Deliberately permissive about ordering and grouping.
  static final RegExp _phonePattern = RegExp(r'^[0-9 +\-()/.,]+$');

  /// Minimum number of digits for a value that claims to be a phone number.
  static const int minPhoneDigits = 6;

  /// `customers.name` — required, within [JobsRepository.maxCustomerNameLength].
  static String? validateName(String? value, AppLocalizations l10n) {
    return _validateRequiredWithinLimit(
      value: value,
      limit: JobsRepository.maxCustomerNameLength,
      l10n: l10n,
    );
  }

  /// `customers.address` — required (NOT NULL on the backend).
  static String? validateAddress(String? value, AppLocalizations l10n) {
    return _validateRequiredWithinLimit(
      value: value,
      limit: JobsRepository.maxCustomerAddressLength,
      l10n: l10n,
    );
  }

  /// `customers.phone` — optional; when filled it must look like a phone
  /// number (allowed characters + at least [minPhoneDigits] digits).
  static String? validateOptionalPhone(String? value, AppLocalizations l10n) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length > JobsRepository.maxCustomerPhoneLength) {
      return l10n.validationFieldTooLong(JobsRepository.maxCustomerPhoneLength);
    }
    if (!_phonePattern.hasMatch(trimmed)) {
      return l10n.validationPhoneInvalid;
    }
    final int digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '').length;
    if (digits < minPhoneDigits) {
      return l10n.validationPhoneInvalid;
    }
    return null;
  }

  /// `customers.email` — optional; the syntax rule is the project-wide one.
  static String? validateOptionalEmail(String? value, AppLocalizations l10n) {
    final String? error = CustomerFormValidators.validateOptionalEmail(
      value,
      l10n,
    );
    if (error != null) {
      return error;
    }
    final String trimmed = value?.trim() ?? '';
    if (trimmed.length > JobsRepository.maxCustomerEmailLength) {
      return l10n.validationFieldTooLong(JobsRepository.maxCustomerEmailLength);
    }
    return null;
  }

  /// `customers.city` — optional, within its limit.
  static String? validateOptionalCity(String? value, AppLocalizations l10n) {
    return validateOptionalWithinLimit(
      value,
      JobsRepository.maxCustomerCityLength,
      l10n,
    );
  }

  /// `customers.postal_code` — optional, within its limit.
  static String? validateOptionalPostalCode(
    String? value,
    AppLocalizations l10n,
  ) {
    return validateOptionalWithinLimit(
      value,
      JobsRepository.maxCustomerPostalCodeLength,
      l10n,
    );
  }

  /// `customers.notes` — optional, within its limit.
  static String? validateOptionalNotes(String? value, AppLocalizations l10n) {
    return validateOptionalWithinLimit(
      value,
      JobsRepository.maxCustomerNotesLength,
      l10n,
    );
  }

  /// `jobs.description` — optional, within
  /// [JobsRepository.maxJobDescriptionLength].
  static String? validateJobDescription(String? value, AppLocalizations l10n) {
    return validateOptionalWithinLimit(
      value,
      JobsRepository.maxJobDescriptionLength,
      l10n,
    );
  }

  /// Shared "blank is fine, over-length is not" rule for optional fields.
  static String? validateOptionalWithinLimit(
    String? value,
    int limit,
    AppLocalizations l10n,
  ) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.length > limit) {
      return l10n.validationFieldTooLong(limit);
    }
    return null;
  }

  /// Shared "required + within limit" rule.
  static String? _validateRequiredWithinLimit({
    required String? value,
    required int limit,
    required AppLocalizations l10n,
  }) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return l10n.validationRequiredField;
    }
    if (trimmed.length > limit) {
      return l10n.validationFieldTooLong(limit);
    }
    return null;
  }
}
