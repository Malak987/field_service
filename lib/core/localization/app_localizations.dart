import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Application localization contract and lookup.
///
/// Supports English (`en`) and German (`de`) out of the box, and is structured
/// so adding future RTL or LTR languages (such as Arabic `ar`) only requires
/// adding a new subclass and registering the locale in [supportedLocales].
abstract class AppLocalizations {
  const AppLocalizations(this.localeName);

  final String localeName;

  /// Resolves the active [AppLocalizations] from [context], falling back safely
  /// to English in isolated widget tests if delegates were not injected.
  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizationsEn();
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// Complete delegate list wired into `MaterialApp.router`.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ];

  /// Supported locales of the application.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('de'),
  ];

  // --- General & Language Switcher -----------------------------------------
  String get appName;
  String get languageEnglish;
  String get languageGerman;
  String get selectLanguage;

  // --- Authentication Headers ----------------------------------------------
  String get loginTitle;
  String get loginSubtitle;
  String get registerTitle;
  String get registerSubtitle;
  String get forgotPasswordTitle;
  String get forgotPasswordSubtitle;
  String get resetPasswordTitle;
  String get resetPasswordSubtitle;

  // --- Form Fields ---------------------------------------------------------
  String get emailLabel;
  String get emailHint;
  String get passwordLabel;
  String get passwordHint;
  String get newPasswordLabel;
  String get newPasswordHint;
  String get confirmPasswordLabel;
  String get confirmPasswordHint;
  String get fullNameLabel;
  String get fullNameHint;

  // --- Actions & Links -----------------------------------------------------
  String get signInButton;
  String get signUpButton;
  String get sendResetLinkButton;
  String get savePasswordButton;
  String get backToLoginButton;
  String get forgotPasswordLink;
  String get noAccountPrompt;
  String get registerLink;
  String get alreadyHaveAccountPrompt;
  String get loginLink;
  String get logoutButton;
  String get tryAgainButton;
  String get showPasswordTooltip;
  String get hidePasswordTooltip;

  // --- Password Requirements -----------------------------------------------
  String get passwordRequirementsTitle;
  String passwordReqMinLength(int minLength);
  String get passwordReqUppercase;
  String get passwordReqLowercase;
  String get passwordReqNumber;
  String get passwordReqSpecialChar;

  // --- Form Validation Messages --------------------------------------------
  String get validationFullNameRequired;
  String get validationFullNameTooShort;
  String get validationEmailRequired;
  String get validationEmailInvalid;
  String get validationPasswordRequired;
  String validationPasswordMinLength(int minLength);
  String get validationPasswordUppercase;
  String get validationPasswordLowercase;
  String get validationPasswordNumber;
  String get validationPasswordSpecial;
  String get validationConfirmPasswordRequired;
  String get validationPasswordsDoNotMatch;

  // --- Mapped Authentication Errors ----------------------------------------
  String get errorInvalidCredentials;
  String get errorEmployeeNotFound;
  String get errorEmployeeInactive;
  String get errorInvalidRole;
  String get errorEmailAlreadyInUse;
  String get errorEmailNotConfirmed;
  String get errorWeakPassword;
  String get errorSamePassword;
  String get errorRecoverySessionExpired;
  String get errorRateLimitExceeded;
  String get errorNetworkUnavailable;
  String get errorUnexpected;

  // --- Success & Informational Messages ------------------------------------
  String get successRegistrationPending;
  String get successPasswordResetEmailSent;
  String get successPasswordUpdated;
  String get roleNoticeBanner;

  // --- Home & Shell --------------------------------------------------------
  String get adminDashboardTitle;
  String get welcomeAdmin;
  String get technicianHomeTitle;
  String get welcomeTechnician;
  String get pageNotFoundTitle;
  String get viewJobsButton;

  // --- Jobs ----------------------------------------------------------------
  String get jobsTitle;
  String get myJobsTitle;
  String get jobDetailsTitle;
  String get jobNumberLabel;
  String get customerLabel;
  String get assignedTechnicianLabel;
  String get jobTypeLabel;
  String get statusLabel;
  String get assignedDateLabel;
  String get startDateLabel;
  String get completedDateLabel;
  String get createdAtLabel;
  String get expiresAtLabel;
  String get descriptionLabel;
  String get jobsEmptyTitle;
  String get jobsEmptySubtitle;
  String get jobsErrorTitle;
  String get jobsErrorSubtitle;
  String get statusAssigned;
  String get statusStarted;
  String get statusInProgress;
  String get statusCompleted;
  String get statusCancelled;
  String get jobTypeRenovation;
  String get jobTypeKitchenInstallation;
  String get jobTypeMaintenance;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return <String>['en', 'de'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(_lookupAppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations _lookupAppLocalizations(Locale locale) {
  switch (locale.languageCode) {
    case 'de':
      return const AppLocalizationsDe();
    case 'en':
    default:
      return const AppLocalizationsEn();
  }
}

/// English (`en`) translations.
class AppLocalizationsEn extends AppLocalizations {
  const AppLocalizationsEn() : super('en');

  @override
  String get appName => 'Field Service';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get selectLanguage => 'Select language';

  @override
  String get loginTitle => 'Sign in to your account';

  @override
  String get loginSubtitle =>
      'Access your field operations and assigned service jobs';

  @override
  String get registerTitle => 'Create employee account';

  @override
  String get registerSubtitle =>
      'Register your account to access field service operations';

  @override
  String get forgotPasswordTitle => 'Forgot your password?';

  @override
  String get forgotPasswordSubtitle =>
      'Enter your work email and we will send you a password recovery link';

  @override
  String get resetPasswordTitle => 'Set a new password';

  @override
  String get resetPasswordSubtitle =>
      'Choose a strong password to secure your account';

  @override
  String get emailLabel => 'Email';

  @override
  String get emailHint => 'name@company.com';

  @override
  String get passwordLabel => 'Password';

  @override
  String get passwordHint => 'Enter your password';

  @override
  String get newPasswordLabel => 'New Password';

  @override
  String get newPasswordHint => 'Enter your new password';

  @override
  String get confirmPasswordLabel => 'Confirm Password';

  @override
  String get confirmPasswordHint => 'Re-enter your password';

  @override
  String get fullNameLabel => 'Full Name';

  @override
  String get fullNameHint => 'Enter your full name';

  @override
  String get signInButton => 'Sign In';

  @override
  String get signUpButton => 'Create Account';

  @override
  String get sendResetLinkButton => 'Send Recovery Link';

  @override
  String get savePasswordButton => 'Save New Password';

  @override
  String get backToLoginButton => 'Back to Sign In';

  @override
  String get forgotPasswordLink => 'Forgot Password?';

  @override
  String get noAccountPrompt => 'Need an employee account?';

  @override
  String get registerLink => 'Register';

  @override
  String get alreadyHaveAccountPrompt => 'Already have an account?';

  @override
  String get loginLink => 'Sign In';

  @override
  String get logoutButton => 'Sign Out';

  @override
  String get tryAgainButton => 'Try Again';

  @override
  String get showPasswordTooltip => 'Show password';

  @override
  String get hidePasswordTooltip => 'Hide password';

  @override
  String get passwordRequirementsTitle => 'Password requirements';

  @override
  String passwordReqMinLength(int minLength) =>
      'At least $minLength characters';

  @override
  String get passwordReqUppercase => 'At least one uppercase letter (A–Z)';

  @override
  String get passwordReqLowercase => 'At least one lowercase letter (a–z)';

  @override
  String get passwordReqNumber => 'At least one number (0–9)';

  @override
  String get passwordReqSpecialChar =>
      'At least one special character (!@#...)';

  @override
  String get validationFullNameRequired => 'Full name is required.';

  @override
  String get validationFullNameTooShort =>
      'Please enter your full first and last name.';

  @override
  String get validationEmailRequired => 'Email address is required.';

  @override
  String get validationEmailInvalid => 'Please enter a valid email address.';

  @override
  String get validationPasswordRequired => 'Password is required.';

  @override
  String validationPasswordMinLength(int minLength) =>
      'Password must be at least $minLength characters long.';

  @override
  String get validationPasswordUppercase =>
      'Password must include at least one uppercase letter.';

  @override
  String get validationPasswordLowercase =>
      'Password must include at least one lowercase letter.';

  @override
  String get validationPasswordNumber =>
      'Password must include at least one number.';

  @override
  String get validationPasswordSpecial =>
      'Password must include at least one special character.';

  @override
  String get validationConfirmPasswordRequired =>
      'Please confirm your password.';

  @override
  String get validationPasswordsDoNotMatch => 'Passwords do not match.';

  @override
  String get errorInvalidCredentials => 'Invalid email or password.';

  @override
  String get errorEmployeeNotFound =>
      'No employee profile is linked to this account. Please contact your administrator.';

  @override
  String get errorEmployeeInactive =>
      'Your employee account has been deactivated. Please contact your administrator.';

  @override
  String get errorInvalidRole =>
      'Your account does not have a valid role assigned. Please contact your administrator.';

  @override
  String get errorEmailAlreadyInUse =>
      'An account with this email address already exists.';

  @override
  String get errorEmailNotConfirmed =>
      'Please verify your email address before signing in.';

  @override
  String get errorWeakPassword =>
      'The chosen password is too weak. Please choose a stronger password.';

  @override
  String get errorSamePassword =>
      'The new password must be different from your current password.';

  @override
  String get errorRecoverySessionExpired =>
      'Your password recovery session has expired. Please request a new reset link.';

  @override
  String get errorRateLimitExceeded =>
      'Too many attempts. Please wait a moment and try again.';

  @override
  String get errorNetworkUnavailable =>
      'Unable to connect. Please check your internet connection and try again.';

  @override
  String get errorUnexpected => 'Something went wrong. Please try again.';

  @override
  String get successRegistrationPending =>
      'Account created successfully. Once your employee profile is activated, you can sign in.';

  @override
  String get successPasswordResetEmailSent =>
      'If an account exists for this email, a password recovery link has been sent.';

  @override
  String get successPasswordUpdated =>
      'Your password has been reset successfully. You can now sign in with your new password.';

  @override
  String get roleNoticeBanner =>
      'Role permissions are assigned automatically by your administrator.';

  @override
  String get adminDashboardTitle => 'Admin Dashboard';

  @override
  String get welcomeAdmin => 'Welcome, Administrator';

  @override
  String get technicianHomeTitle => 'My Jobs';

  @override
  String get welcomeTechnician => 'Welcome, Technician';

  @override
  String get pageNotFoundTitle => 'Page not found';

  @override
  String get viewJobsButton => 'View Jobs';

  @override
  String get jobsTitle => 'Jobs';

  @override
  String get myJobsTitle => 'My Jobs';

  @override
  String get jobDetailsTitle => 'Job Details';

  @override
  String get jobNumberLabel => 'Job Number';

  @override
  String get customerLabel => 'Customer';

  @override
  String get assignedTechnicianLabel => 'Assigned Technician';

  @override
  String get jobTypeLabel => 'Job Type';

  @override
  String get statusLabel => 'Status';

  @override
  String get assignedDateLabel => 'Assigned Date';

  @override
  String get startDateLabel => 'Start Date';

  @override
  String get completedDateLabel => 'Completed Date';

  @override
  String get createdAtLabel => 'Created';

  @override
  String get expiresAtLabel => 'Expires';

  @override
  String get descriptionLabel => 'Description';

  @override
  String get jobsEmptyTitle => 'No jobs yet';

  @override
  String get jobsEmptySubtitle => 'New jobs will appear here.';

  @override
  String get jobsErrorTitle => 'Something went wrong';

  @override
  String get jobsErrorSubtitle =>
      'Jobs could not be loaded. Please check your connection and try again.';

  @override
  String get statusAssigned => 'Assigned';

  @override
  String get statusStarted => 'Started';

  @override
  String get statusInProgress => 'In Progress';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get jobTypeRenovation => 'Renovation';

  @override
  String get jobTypeKitchenInstallation => 'Kitchen Installation';

  @override
  String get jobTypeMaintenance => 'Maintenance';
}

/// German (`de`) translations — natural, idiomatic German for professional field service use.
class AppLocalizationsDe extends AppLocalizations {
  const AppLocalizationsDe() : super('de');

  @override
  String get appName => 'Field Service';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get selectLanguage => 'Sprache auswählen';

  @override
  String get loginTitle => 'Bei Ihrem Konto anmelden';

  @override
  String get loginSubtitle =>
      'Greifen Sie auf Ihre Außendiensteinsätze und zugewiesenen Aufträge zu';

  @override
  String get registerTitle => 'Mitarbeiterkonto erstellen';

  @override
  String get registerSubtitle =>
      'Registrieren Sie Ihr Konto für den Zugriff auf den Außendienst';

  @override
  String get forgotPasswordTitle => 'Passwort vergessen?';

  @override
  String get forgotPasswordSubtitle =>
      'Geben Sie Ihre geschäftliche E-Mail-Adresse ein, um einen Link zum Zurücksetzen zu erhalten';

  @override
  String get resetPasswordTitle => 'Neues Passwort festlegen';

  @override
  String get resetPasswordSubtitle =>
      'Wählen Sie ein sicheres Passwort zum Schutz Ihres Kontos';

  @override
  String get emailLabel => 'E-Mail-Adresse';

  @override
  String get emailHint => 'name@unternehmen.de';

  @override
  String get passwordLabel => 'Passwort';

  @override
  String get passwordHint => 'Passwort eingeben';

  @override
  String get newPasswordLabel => 'Neues Passwort';

  @override
  String get newPasswordHint => 'Neues Passwort eingeben';

  @override
  String get confirmPasswordLabel => 'Passwort bestätigen';

  @override
  String get confirmPasswordHint => 'Passwort erneut eingeben';

  @override
  String get fullNameLabel => 'Vollständiger Name';

  @override
  String get fullNameHint => 'Vor- und Nachname eingeben';

  @override
  String get signInButton => 'Anmelden';

  @override
  String get signUpButton => 'Konto erstellen';

  @override
  String get sendResetLinkButton => 'Link zum Zurücksetzen senden';

  @override
  String get savePasswordButton => 'Neues Passwort speichern';

  @override
  String get backToLoginButton => 'Zurück zur Anmeldung';

  @override
  String get forgotPasswordLink => 'Passwort vergessen?';

  @override
  String get noAccountPrompt => 'Noch kein Mitarbeiterkonto?';

  @override
  String get registerLink => 'Registrieren';

  @override
  String get alreadyHaveAccountPrompt => 'Bereits ein Konto vorhanden?';

  @override
  String get loginLink => 'Anmelden';

  @override
  String get logoutButton => 'Abmelden';

  @override
  String get tryAgainButton => 'Erneut versuchen';

  @override
  String get showPasswordTooltip => 'Passwort anzeigen';

  @override
  String get hidePasswordTooltip => 'Passwort verbergen';

  @override
  String get passwordRequirementsTitle => 'Passwortanforderungen';

  @override
  String passwordReqMinLength(int minLength) => 'Mindestens $minLength Zeichen';

  @override
  String get passwordReqUppercase => 'Mindestens ein Großbuchstabe (A–Z)';

  @override
  String get passwordReqLowercase => 'Mindestens ein Kleinbuchstabe (a–z)';

  @override
  String get passwordReqNumber => 'Mindestens eine Ziffer (0–9)';

  @override
  String get passwordReqSpecialChar =>
      'Mindestens ein Sonderzeichen (!@#...)';

  @override
  String get validationFullNameRequired =>
      'Bitte geben Sie Ihren vollständigen Namen ein.';

  @override
  String get validationFullNameTooShort =>
      'Bitte geben Sie Ihren Vor- und Nachnamen vollständig ein.';

  @override
  String get validationEmailRequired =>
      'Bitte geben Sie Ihre E-Mail-Adresse ein.';

  @override
  String get validationEmailInvalid =>
      'Bitte geben Sie eine gültige E-Mail-Adresse ein.';

  @override
  String get validationPasswordRequired => 'Bitte geben Sie Ihr Passwort ein.';

  @override
  String validationPasswordMinLength(int minLength) =>
      'Das Passwort muss mindestens $minLength Zeichen lang sein.';

  @override
  String get validationPasswordUppercase =>
      'Das Passwort muss mindestens einen Großbuchstaben enthalten.';

  @override
  String get validationPasswordLowercase =>
      'Das Passwort muss mindestens einen Kleinbuchstaben enthalten.';

  @override
  String get validationPasswordNumber =>
      'Das Passwort muss mindestens eine Ziffer enthalten.';

  @override
  String get validationPasswordSpecial =>
      'Das Passwort muss mindestens ein Sonderzeichen enthalten.';

  @override
  String get validationConfirmPasswordRequired =>
      'Bitte bestätigen Sie Ihr Passwort.';

  @override
  String get validationPasswordsDoNotMatch =>
      'Die Passwörter stimmen nicht überein.';

  @override
  String get errorInvalidCredentials =>
      'E-Mail-Adresse oder Passwort ist ungültig.';

  @override
  String get errorEmployeeNotFound =>
      'Mit diesem Konto ist kein Mitarbeiterprofil verknüpft. Bitte wenden Sie sich an Ihren Administrator.';

  @override
  String get errorEmployeeInactive =>
      'Ihr Mitarbeiterkonto ist deaktiviert. Bitte wenden Sie sich an Ihren Administrator.';

  @override
  String get errorInvalidRole =>
      'Ihrem Konto ist keine gültige Rolle zugewiesen. Bitte wenden Sie sich an Ihren Administrator.';

  @override
  String get errorEmailAlreadyInUse =>
      'Für diese E-Mail-Adresse existiert bereits ein Konto.';

  @override
  String get errorEmailNotConfirmed =>
      'Bitte bestätigen Sie zuerst Ihre E-Mail-Adresse, bevor Sie sich anmelden.';

  @override
  String get errorWeakPassword =>
      'Das gewählte Passwort ist zu schwach. Bitte wählen Sie ein sichereres Passwort.';

  @override
  String get errorSamePassword =>
      'Das neue Passwort muss sich von Ihrem bisherigen Passwort unterscheiden.';

  @override
  String get errorRecoverySessionExpired =>
      'Ihre Sitzung zum Zurücksetzen des Passworts ist abgelaufen. Bitte fordern Sie einen neuen Link an.';

  @override
  String get errorRateLimitExceeded =>
      'Zu viele Versuche. Bitte warten Sie einen Moment und versuchen Sie es erneut.';

  @override
  String get errorNetworkUnavailable =>
      'Verbindung fehlgeschlagen. Bitte prüfen Sie Ihre Internetverbindung und versuchen Sie es erneut.';

  @override
  String get errorUnexpected =>
      'Ein unerwarteter Fehler ist aufgetreten. Bitte versuchen Sie es erneut.';

  @override
  String get successRegistrationPending =>
      'Ihr Konto wurde erfolgreich erstellt. Sobald Ihr Mitarbeiterprofil aktiviert wurde, können Sie sich anmelden.';

  @override
  String get successPasswordResetEmailSent =>
      'Falls ein Konto für diese E-Mail-Adresse existiert, wurde ein Link zum Zurücksetzen gesendet.';

  @override
  String get successPasswordUpdated =>
      'Ihr Passwort wurde erfolgreich zurückgesetzt. Sie können sich jetzt mit Ihrem neuen Passwort anmelden.';

  @override
  String get roleNoticeBanner =>
      'Rollen und Berechtigungen werden automatisch durch Ihren Administrator vergeben.';

  @override
  String get adminDashboardTitle => 'Admin-Dashboard';

  @override
  String get welcomeAdmin => 'Willkommen, Administrator';

  @override
  String get technicianHomeTitle => 'Meine Aufträge';

  @override
  String get welcomeTechnician => 'Willkommen, Techniker';

  @override
  String get pageNotFoundTitle => 'Seite nicht gefunden';

  @override
  String get viewJobsButton => 'Aufträge anzeigen';

  @override
  String get jobsTitle => 'Aufträge';

  @override
  String get myJobsTitle => 'Meine Aufträge';

  @override
  String get jobDetailsTitle => 'Auftragsdetails';

  @override
  String get jobNumberLabel => 'Auftragsnummer';

  @override
  String get customerLabel => 'Kunde';

  @override
  String get assignedTechnicianLabel => 'Zugewiesener Techniker';

  @override
  String get jobTypeLabel => 'Auftragsart';

  @override
  String get statusLabel => 'Status';

  @override
  String get assignedDateLabel => 'Zugewiesen am';

  @override
  String get startDateLabel => 'Startdatum';

  @override
  String get completedDateLabel => 'Abgeschlossen am';

  @override
  String get createdAtLabel => 'Erstellt';

  @override
  String get expiresAtLabel => 'Läuft ab';

  @override
  String get descriptionLabel => 'Beschreibung';

  @override
  String get jobsEmptyTitle => 'Noch keine Aufträge';

  @override
  String get jobsEmptySubtitle => 'Neue Aufträge erscheinen hier.';

  @override
  String get jobsErrorTitle => 'Etwas ist schiefgelaufen';

  @override
  String get jobsErrorSubtitle =>
      'Aufträge konnten nicht geladen werden. Bitte prüfen Sie Ihre Verbindung und versuchen Sie es erneut.';

  @override
  String get statusAssigned => 'Zugewiesen';

  @override
  String get statusStarted => 'Gestartet';

  @override
  String get statusInProgress => 'In Arbeit';

  @override
  String get statusCompleted => 'Abgeschlossen';

  @override
  String get statusCancelled => 'Storniert';

  @override
  String get jobTypeRenovation => 'Renovierung';

  @override
  String get jobTypeKitchenInstallation => 'Kücheneinbau';

  @override
  String get jobTypeMaintenance => 'Wartung';
}

/// Ergonomic shorthand on [BuildContext] for localized strings.
extension AppLocalizationsContextX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
