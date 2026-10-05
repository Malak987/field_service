import 'package:field_service/core/localization/app_localizations.dart';

/// Configurable password policy rules shared across the application.
class PasswordPolicy {
  const PasswordPolicy({
    this.minLength = 8,
    this.requireUppercase = true,
    this.requireLowercase = true,
    this.requireNumber = true,
    this.requireSpecialCharacter = true,
  });

  /// Default production policy for new and reset passwords.
  static const PasswordPolicy standard = PasswordPolicy();

  final int minLength;
  final bool requireUppercase;
  final bool requireLowercase;
  final bool requireNumber;
  final bool requireSpecialCharacter;
}

/// Evaluation snapshot of a candidate password against a [PasswordPolicy].
class PasswordValidationStatus {
  const PasswordValidationStatus({
    required this.policy,
    required this.hasMinLength,
    required this.hasUppercase,
    required this.hasLowercase,
    required this.hasNumber,
    required this.hasSpecialCharacter,
  });

  final PasswordPolicy policy;
  final bool hasMinLength;
  final bool hasUppercase;
  final bool hasLowercase;
  final bool hasNumber;
  final bool hasSpecialCharacter;

  /// Whether every configured rule of [policy] is satisfied.
  bool get isValid =>
      hasMinLength &&
      (!policy.requireUppercase || hasUppercase) &&
      (!policy.requireLowercase || hasLowercase) &&
      (!policy.requireNumber || hasNumber) &&
      (!policy.requireSpecialCharacter || hasSpecialCharacter);
}

/// Centralized, reusable password and authentication input validator.
///
/// Eliminates duplicated validation logic across Login, Register, Forgot
/// Password, and Reset Password screens while staying pure Dart + localized
/// through [AppLocalizations].
abstract final class PasswordValidator {
  static final RegExp _uppercaseRegExp = RegExp('[A-Z]');
  static final RegExp _lowercaseRegExp = RegExp('[a-z]');
  static final RegExp _numberRegExp = RegExp('[0-9]');
  static final RegExp _specialCharRegExp = RegExp(
    r'[!@#\$%\^&\*\(\)_\+\-=\[\]\{\};:"\\|,.<>\/?~`]',
  );
  static final RegExp _emailRegExp = RegExp(
    r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$',
  );

  /// Evaluates all password rules for live feedback in `PasswordRequirements`.
  static PasswordValidationStatus evaluate(
    String value, {
    PasswordPolicy policy = PasswordPolicy.standard,
  }) {
    return PasswordValidationStatus(
      policy: policy,
      hasMinLength: value.length >= policy.minLength,
      hasUppercase: _uppercaseRegExp.hasMatch(value),
      hasLowercase: _lowercaseRegExp.hasMatch(value),
      hasNumber: _numberRegExp.hasMatch(value),
      hasSpecialCharacter: _specialCharRegExp.hasMatch(value),
    );
  }

  /// Validates the password field on the Login screen (presence required).
  static String? validateLoginPassword(
    String? value,
    AppLocalizations l10n,
  ) {
    if (value == null || value.isEmpty) {
      return l10n.validationPasswordRequired;
    }
    return null;
  }

  /// Validates a new password against [policy] (used on Register & Reset Password).
  static String? validateNewPassword(
    String? value,
    AppLocalizations l10n, {
    PasswordPolicy policy = PasswordPolicy.standard,
  }) {
    if (value == null || value.isEmpty) {
      return l10n.validationPasswordRequired;
    }

    final PasswordValidationStatus status = evaluate(value, policy: policy);

    if (!status.hasMinLength) {
      return l10n.validationPasswordMinLength(policy.minLength);
    }
    if (policy.requireUppercase && !status.hasUppercase) {
      return l10n.validationPasswordUppercase;
    }
    if (policy.requireLowercase && !status.hasLowercase) {
      return l10n.validationPasswordLowercase;
    }
    if (policy.requireNumber && !status.hasNumber) {
      return l10n.validationPasswordNumber;
    }
    if (policy.requireSpecialCharacter && !status.hasSpecialCharacter) {
      return l10n.validationPasswordSpecial;
    }

    return null;
  }

  /// Validates a password confirmation field against [originalPassword].
  static String? validateConfirmPassword(
    String? value,
    String originalPassword,
    AppLocalizations l10n,
  ) {
    if (value == null || value.isEmpty) {
      return l10n.validationConfirmPasswordRequired;
    }
    if (value != originalPassword) {
      return l10n.validationPasswordsDoNotMatch;
    }
    return null;
  }

  /// Validates an email address field across Login, Register, and Forgot Password.
  static String? validateEmail(
    String? value,
    AppLocalizations l10n,
  ) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return l10n.validationEmailRequired;
    }
    if (!_emailRegExp.hasMatch(trimmed)) {
      return l10n.validationEmailInvalid;
    }
    return null;
  }

  /// Validates the employee full name field on the Register screen.
  static String? validateFullName(
    String? value,
    AppLocalizations l10n,
  ) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return l10n.validationFullNameRequired;
    }
    if (trimmed.length < 2) {
      return l10n.validationFullNameTooShort;
    }
    return null;
  }
}
