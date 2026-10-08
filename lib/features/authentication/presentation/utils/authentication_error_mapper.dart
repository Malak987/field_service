import 'package:field_service/core/errors/failure.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Semantic authentication error codes used to decouple backend exceptions from
/// localized UI messages.
enum AuthErrorCode {
  invalidCredentials,
  employeeNotFound,
  employeeInactive,
  invalidRole,
  emailAlreadyInUse,
  emailNotConfirmed,
  weakPassword,
  samePassword,
  recoverySessionExpired,
  rateLimitExceeded,
  networkUnavailable,
  unexpected,
}

/// Maps technical backend/Supabase exceptions into structured [AuthErrorCode]s
/// and user-friendly localized strings.
///
/// Raw exception text (such as `AuthException: Invalid login credentials`) is
/// never shown directly to end users.
abstract final class AuthenticationErrorMapper {
  /// Machine-readable codes raised explicitly by `AuthenticationRepositoryImpl`.
  static const String codeEmployeeNotFound = 'employee_not_found';
  static const String codeEmployeeInactive = 'employee_inactive';
  static const String codeInvalidRole = 'invalid_role';
  static const String codeRecoveryExpired = 'recovery_session_expired';

  /// Maps any thrown [error] into a semantic [AuthErrorCode].
  static AuthErrorCode mapErrorToCode(Object? error) {
    if (error == null) {
      return AuthErrorCode.unexpected;
    }

    if (error is AuthErrorCode) {
      return error;
    }

    if (error is Failure) {
      if (error.type == FailureType.network) {
        return AuthErrorCode.networkUnavailable;
      }
      if (error.code != null) {
        final AuthErrorCode? byCode = _fromCodeString(error.code!);
        if (byCode != null) {
          return byCode;
        }
      }
      return _fromRawMessage(error.message);
    }

    if (error is AuthException) {
      if (error.code != null) {
        final AuthErrorCode? byCode = _fromCodeString(error.code!);
        if (byCode != null) {
          return byCode;
        }
      }
      return _fromRawMessage(error.message);
    }

    if (error is PostgrestException) {
      return _fromRawMessage(error.message);
    }

    return _fromRawMessage(error.toString());
  }

  static AuthErrorCode? _fromCodeString(String rawCode) {
    final String code = rawCode.trim().toLowerCase();
    switch (code) {
      case 'invalid_credentials':
      case 'invalid_grant':
        return AuthErrorCode.invalidCredentials;
      case codeEmployeeNotFound:
        return AuthErrorCode.employeeNotFound;
      case codeEmployeeInactive:
        return AuthErrorCode.employeeInactive;
      case codeInvalidRole:
        return AuthErrorCode.invalidRole;
      case 'user_already_exists':
      case 'email_exists':
        return AuthErrorCode.emailAlreadyInUse;
      case 'email_not_confirmed':
        return AuthErrorCode.emailNotConfirmed;
      case 'weak_password':
        return AuthErrorCode.weakPassword;
      case 'same_password':
        return AuthErrorCode.samePassword;
      case codeRecoveryExpired:
      case 'flow_state_expired':
      case 'otp_expired':
      case 'session_not_found':
        return AuthErrorCode.recoverySessionExpired;
      case 'over_email_send_rate_limit':
      case 'over_request_rate_limit':
        return AuthErrorCode.rateLimitExceeded;
      default:
        return null;
    }
  }

  static AuthErrorCode _fromRawMessage(String rawMessage) {
    final String msg = rawMessage.toLowerCase();

    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials') ||
        msg.contains('invalid email or password')) {
      return AuthErrorCode.invalidCredentials;
    }

    if (msg.contains('employee profile was not found') ||
        msg.contains(codeEmployeeNotFound)) {
      return AuthErrorCode.employeeNotFound;
    }

    if (msg.contains('employee account is inactive') ||
        msg.contains('account is inactive') ||
        msg.contains(codeEmployeeInactive)) {
      return AuthErrorCode.employeeInactive;
    }

    if (msg.contains('invalid role') ||
        msg.contains('unknown user role') ||
        msg.contains(codeInvalidRole)) {
      return AuthErrorCode.invalidRole;
    }

    if (msg.contains('already registered') ||
        msg.contains('already exists') ||
        msg.contains('user_already_exists')) {
      return AuthErrorCode.emailAlreadyInUse;
    }

    if (msg.contains('email not confirmed') ||
        msg.contains('email_not_confirmed')) {
      return AuthErrorCode.emailNotConfirmed;
    }

    if (msg.contains('weak_password') ||
        msg.contains('password should be at least')) {
      return AuthErrorCode.weakPassword;
    }

    if (msg.contains('same_password') ||
        msg.contains('different from the old password')) {
      return AuthErrorCode.samePassword;
    }

    if (msg.contains('auth session missing') ||
        msg.contains('recovery session') ||
        msg.contains('expired') ||
        msg.contains(codeRecoveryExpired)) {
      return AuthErrorCode.recoverySessionExpired;
    }

    if (msg.contains('rate limit') ||
        msg.contains('too many requests') ||
        msg.contains('for security purposes, you can only request this')) {
      return AuthErrorCode.rateLimitExceeded;
    }

    if (msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('network is unreachable') ||
        msg.contains('clientexception')) {
      return AuthErrorCode.networkUnavailable;
    }

    return AuthErrorCode.unexpected;
  }

  /// Resolves the localized user-facing message for [code] using [l10n].
  static String localizeCode(AuthErrorCode code, AppLocalizations l10n) {
    switch (code) {
      case AuthErrorCode.invalidCredentials:
        return l10n.errorInvalidCredentials;
      case AuthErrorCode.employeeNotFound:
        return l10n.errorEmployeeNotFound;
      case AuthErrorCode.employeeInactive:
        return l10n.errorEmployeeInactive;
      case AuthErrorCode.invalidRole:
        return l10n.errorInvalidRole;
      case AuthErrorCode.emailAlreadyInUse:
        return l10n.errorEmailAlreadyInUse;
      case AuthErrorCode.emailNotConfirmed:
        return l10n.errorEmailNotConfirmed;
      case AuthErrorCode.weakPassword:
        return l10n.errorWeakPassword;
      case AuthErrorCode.samePassword:
        return l10n.errorSamePassword;
      case AuthErrorCode.recoverySessionExpired:
        return l10n.errorRecoverySessionExpired;
      case AuthErrorCode.rateLimitExceeded:
        return l10n.errorRateLimitExceeded;
      case AuthErrorCode.networkUnavailable:
        return l10n.errorNetworkUnavailable;
      case AuthErrorCode.unexpected:
        return l10n.errorUnexpected;
    }
  }

  /// Convenience helper to map any [error] or [code] directly to a localized
  /// message using [l10n].
  static String toLocalizedMessage(
    AppLocalizations l10n, {
    AuthErrorCode? code,
    Object? error,
  }) {
    final AuthErrorCode resolvedCode = code ?? mapErrorToCode(error);
    return localizeCode(resolvedCode, l10n);
  }

  /// Returns a safe, non-technical English message for state/logging fallback
  /// when no `BuildContext` is available.
  static String toFallbackMessage(Object? error) {
    final AuthErrorCode code = mapErrorToCode(error);
    return localizeCode(code, const AppLocalizationsEn());
  }
}
