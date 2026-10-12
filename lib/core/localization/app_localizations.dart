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
    // German first: it is the default locale, so an unmatched platform locale
    // resolves here rather than to English.
    Locale('de'),
    Locale('en'),
  ];

  // --- General & Language Switcher -----------------------------------------
  String get appName;
  String get languageEnglish;
  String get languageGerman;
  String get selectLanguage;

  // --- Authentication Headers ----------------------------------------------
  String get loginWelcomeTitle;
  String get loginWelcomeSubtitle;
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
  String get pageNotFoundSubtitle;
  String get pageNotFoundAction;
  String get viewJobsButton;
  String get viewCustomersButton;

  // --- Home Dashboard, Navigation & Account ---------------------------------
  String welcomeNameLabel(String name);
  String get roleAdminLabel;
  String get roleTechnicianLabel;
  String get accountTitle;
  String get homeTabLabel;
  String get kitchenTabLabel;
  String get homeRenovationTabLabel;
  String get overviewTitle;
  String get totalJobsLabel;
  String get quickActionsTitle;
  String get categoriesTitle;
  String jobsCountLabel(int count);
  String get continueJobButton;
  String get currentJobTitle;
  String get noAssignedJobsTitle;
  String get noAssignedJobsSubtitle;
  String nextActionLabel(String action);

  // --- Jobs ----------------------------------------------------------------
  String get jobsTitle;
  String get myJobsTitle;
  String get jobDetailsTitle;

  String get jobActivityTitle;
  String get activityAssigned;
  String get activityStarted;
  String get activityBeforePhoto;
  String get activityAfterPhoto;
  String get activitySignature;
  String get activityCompleted;
  String get workflowProgressTitle;
  String workflowProgressLabel(int completed, int total);
  String get currentStepLabel;
  String get jobNumberLabel;
  String get customerLabel;
  String get assignedTechnicianLabel;
  String get jobTypeLabel;
  String get jobCategoryHomeRenovation;
  String get jobCategoryKitchenRenovation;
  String get statusLabel;
  String get assignedDateLabel;
  String get startDateLabel;
  String get completedDateLabel;
  String get createdAtLabel;
  String get expiresAtLabel;
  String get descriptionLabel;
  String get jobInformationTitle;
  String get customerInfoUnavailable;
  String get startJobButton;
  String jobStartedAt(String time);
  String get jobStartedMessage;
  String get startJobFailedMessage;
  String get jobAlreadyStartedMessage;
  // --- Before Photos ---------------------------------------------------------
  String get beforePhotosTitle;
  String get addBeforePhotoButton;
  String get takePhotoButton;
  String get chooseFromGalleryButton;
  String get noBeforePhotosYet;

  /// One line of guidance under the empty before-photos state, saying WHY the
  /// step matters instead of only that it is empty.
  String get beforePhotosRequiredHint;
  String get uploadingLabel;
  String get uploadFailedLabel;
  String get photoSyncedLabel;
  String get retryButton;
  String get cameraUnavailableError;
  String get photoAccessDeniedError;
  String get invalidImageError;
  String get addBeforePhotoFailedError;
  // --- After Photos -------------------------------------------------------
  String get afterPhotosTitle;
  String get addAfterPhotoButton;
  String get noAfterPhotosYet;

  /// One line of guidance under the empty after-photos state.
  String get afterPhotosRequiredHint;
  String get addAfterPhotoFailedError;
  // --- Customer Signature -------------------------------------------------
  String get customerSignatureTitle;
  String get signatureHint;
  String get clearButton;
  String get saveSignatureButton;
  String get signatureRequiredError;
  String get signatureSavedMessage;
  String get signatureSaveFailedMessage;
  String get noSignatureYet;
  String get signatureHelper;

  /// What the customer's signature MEANS: the confirmation of the finished
  /// work, which is also why it is required before a job can be completed.
  String get signatureConfirmsWorkHint;
  String get replaceSignatureButton;
  String stepLabel(int step);
  String get customerRequestLabel;
  String get workDescriptionSubtitle;
  String jobCompletedAt(String time);
  // --- Work Description -----------------------------------------------------
  String get workDescriptionTitle;
  String get workDescriptionHint;
  String get workDescriptionNoneYet;

  /// One line of guidance under the work description field, saying that the
  /// description is part of completing the job.
  String get workDescriptionRequiredHint;
  String get workDescriptionEmptyError;
  String workDescriptionTooLongError(int max);
  String get workDescriptionSavedMessage;
  String get workDescriptionSaveFailedMessage;
  String get workDescriptionSavingLabel;

  // --- Complete Job ---------------------------------------------------------
  String get completeJobButton;
  String get completionRequirementsTitle;
  String get jobCompletedMessage;
  String get missingBeforePhotoError;
  String get missingWorkDescriptionError;
  String get missingAfterPhotoError;
  String get missingSignatureError;
  String get internetRequiredToCompleteJob;
  String get requirementDoneLabel;
  String get requirementOpenLabel;
  String get unableToCompleteJobError;
  String get waitingForFileSync;
  String get jobsEmptyTitle;
  String get jobsEmptySubtitle;

  String get createFirstJobButton;
  String get jobsErrorTitle;
  String get jobsErrorSubtitle;
  String get jobsLoadingLabel;
  String get statusAssigned;
  String get statusStarted;
  String get statusInProgress;
  String get statusCompleted;
  String get statusCancelled;
  String get searchJobsHint;
  String get filterStatusLabel;
  String get allStatusesLabel;
  String get filterCategoryLabel;
  String get allCategoriesLabel;
  String get clearFiltersButton;
  String get noJobsMatchTitle;
  String get noJobsMatchSubtitle;
  // --- Job creation (admin workflow) ---------------------------------------
  String get createJobButton;
  String get createJobIntro;
  String get createJobReviewTitle;
  String get createJobOptionsFailedMessage;
  String get createAndAssignJobButton;
  String get selectCustomerLabel;
  String get selectTechnicianLabel;
  String get createJobSuccessMessage;
  String get createJobFailedMessage;
  String get noActiveTechniciansMessage;

  // --- Customers -----------------------------------------------------------
  String get customersTitle;
  String get customerTitle;
  String get addCustomer;
  String get editCustomer;
  String get deleteCustomer;
  String get searchCustomersHint;
  String get customersSubtitle;
  String get customersLoadingLabel;
  String customersCountLabel(int count);
  String get clearSearchButton;
  String get customerBasicsGroup;
  String get customerContactGroup;
  String get customerAddressGroup;
  String get customerNotesGroup;
  String get customerRequiredFieldsHint;
  String get customerNameHint;
  String get customerPhoneHint;
  String get customerEmailHint;
  String get customerAddressHint;
  String get customerCityHint;
  String get customerPostalCodeHint;
  String get customerNotesHint;
  String get customerNameLabel;
  String get customerPhoneLabel;
  String get customerEmailLabel;
  String get customerAddressLabel;
  String get customerCityLabel;
  String get customerPostalCodeLabel;
  String get customerNotesLabel;
  String get saveButton;
  String get cancelButton;
  String get deleteButton;
  String get updatedAtLabel;
  String get customersEmptyTitle;
  String get customersEmptySubtitle;
  String get customersNoResultsTitle;
  String get customersErrorTitle;
  String get customersErrorSubtitle;
  String get customerNotFoundTitle;
  String get customerNotFoundSubtitle;
  String get customerSaveFailed;
  String get customerSavedSuccess;
  String get customerLinkedJobsError;
  String deleteCustomerConfirmation(String name);
  String get offlineLabel;
  String get syncStatusTitle;
  String get syncingLabel;
  String get pendingSyncLabel;
  String get syncedLabel;
  String get syncFailedLabel;
  String get validationRequiredField;

  // --- Admin management (technicians & customers) ---------------------------
  String get adminManagementTitle;
  String get adminTechniciansTileSubtitle;
  String get adminCustomersTileSubtitle;
  String get adminTechniciansTitle;
  String get adminTechniciansSubtitle;
  String get adminTechniciansLoadingLabel;
  String get adminTechniciansEmptyTitle;
  String get adminTechniciansEmptySubtitle;
  String get adminCustomersTitle;
  String get adminCustomersLoadingLabel;
  String get adminCustomersEmptyTitle;
  String get adminCustomersEmptySubtitle;
  String get adminCustomerDetailsTitle;
  String get adminLoadFailedTitle;
  String get adminStatusActive;
  String get adminStatusBlocked;
  String get adminStatusDeleted;
  String get adminStatusUnknown;
  String get adminBlockAction;
  String get adminUnblockAction;
  String get adminSoftDeleteAction;
  String get adminConfirmAction;
  String get adminHistoryKeptNotice;
  String get adminDeletedCustomerNotice;
  String get adminDeletedTechnicianNotice;
  String get adminOwnAccountNotice;
  String get adminAdministratorNotice;
  String adminAccountsCountLabel(int count);
  String adminAssignedJobsLabel(int count);
  String adminCompletedJobsLabel(int count);
  String adminCustomerJobsCountLabel(int count);
  String adminBlockedOnLabel(String date);
  String adminDeletedOnLabel(String date);
  String get adminBlockTechnicianConfirmTitle;
  String adminBlockTechnicianConfirmBody(String name);
  String get adminUnblockTechnicianConfirmTitle;
  String adminUnblockTechnicianConfirmBody(String name);
  String get adminDeleteTechnicianConfirmTitle;
  String adminDeleteTechnicianConfirmBody(String name);
  String get adminBlockCustomerConfirmTitle;
  String adminBlockCustomerConfirmBody(String name);
  String get adminUnblockCustomerConfirmTitle;
  String adminUnblockCustomerConfirmBody(String name);
  String get adminDeleteCustomerConfirmTitle;
  String adminDeleteCustomerConfirmBody(String name);
  String get adminTechnicianBlockedMessage;
  String get adminTechnicianUnblockedMessage;
  String get adminTechnicianDeletedMessage;
  String get adminCustomerBlockedMessage;
  String get adminCustomerUnblockedMessage;
  String get adminCustomerDeletedMessage;
  String get adminCustomerCreatedMessage;
  String get adminCustomerUpdatedMessage;
  String get adminErrorNotAuthorized;
  String get adminErrorNotFound;
  String get adminErrorRecordDeleted;
  String get adminErrorInvalidInput;
  String get adminErrorCustomerBlocked;
  String get adminErrorNetwork;
  String get adminErrorUnknown;

  // --- Technician: create customer & job -----------------------------------
  String get technicianCreateJobTitle;
  String get technicianCreateJobSubtitle;
  String get technicianCreateJobButton;
  String get technicianCreateJobEntryTitle;
  String get technicianCreateJobEntrySubtitle;
  String get technicianJobCustomerSection;
  String get technicianJobDetailsSection;
  String get technicianJobCustomerModeNew;
  String get technicianJobCustomerModeExisting;
  String get technicianSelectExistingCustomerTitle;
  String get technicianAccessibleCustomersEmptySubtitle;
  String get technicianAccessibleCustomersError;
  String get technicianJobDescriptionHint;
  String get technicianJobAssignedToLabel;
  String get technicianJobAssignedToHint;
  String technicianCreateJobSuccess(int jobNumber);
  String get technicianCreateJobQueued;
  String get technicianCreateJobFailed;
  String get technicianCreateJobErrorUnauthorized;
  String get technicianCreateJobErrorCustomerNotFound;
  String get technicianCreateJobErrorCustomerBlocked;
  String get technicianCreateJobErrorInvalidInput;
  String get technicianCreateJobErrorNotAuthenticated;
  String get technicianCreateJobErrorUnknown;
  String validationFieldTooLong(int count);
  String get validationPhoneInvalid;

  // --- Dashboards --------------------------------------------------------
  String get accountSettingsTooltip;
  String get recentJobsTitle;
  String get recentJobsSubtitle;
  String get recentJobsViewAll;
  String get unassignedLabel;
  String get adminOverviewSubtitle;
  String get technicianOverviewSubtitle;
  String get dashboardOverviewErrorTitle;
  String get dashboardOverviewErrorMessage;
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
  String get loginWelcomeTitle => 'Welcome back';

  @override
  String get loginWelcomeSubtitle => 'Sign in to continue to your workspace.';

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
  String get pageNotFoundSubtitle =>
      'This link does not lead anywhere. It may be outdated or incomplete.';

  @override
  String get pageNotFoundAction => 'Back to start';

  @override
  String get viewJobsButton => 'View Jobs';

  @override
  String get viewCustomersButton => 'View Customers';

  @override
  String welcomeNameLabel(String name) => 'Welcome, $name';

  @override
  String get roleAdminLabel => 'Administrator';

  @override
  String get roleTechnicianLabel => 'Technician';

  @override
  String get accountTitle => 'Account';

  @override
  String get homeTabLabel => 'Home';

  @override
  String get kitchenTabLabel => 'Kitchen';

  @override
  String get homeRenovationTabLabel => 'Home Renovation';

  @override
  String get overviewTitle => 'Overview';

  @override
  String get totalJobsLabel => 'Total';

  @override
  String get quickActionsTitle => 'Quick Actions';

  @override
  String get categoriesTitle => 'Categories';

  @override
  String jobsCountLabel(int count) => count == 1 ? '1 job' : '$count jobs';

  @override
  String get continueJobButton => 'Continue Job';

  @override
  String get currentJobTitle => 'Current Job';

  @override
  String get noAssignedJobsTitle => 'No assigned jobs';

  @override
  String get noAssignedJobsSubtitle =>
      'New jobs assigned to you will appear here.';

  @override
  String nextActionLabel(String action) => 'Next: $action';

  @override
  String get jobsTitle => 'Jobs';

  @override
  String get myJobsTitle => 'My Jobs';

  @override
  String get jobDetailsTitle => 'Job Details';

  @override
  String get jobActivityTitle => 'Activity';
  @override
  String get activityAssigned => 'Job assigned';
  @override
  String get activityStarted => 'Work started';
  @override
  String get activityBeforePhoto => 'Before photo captured';
  @override
  String get activityAfterPhoto => 'After photo captured';
  @override
  String get activitySignature => 'Signature captured';
  @override
  String get activityCompleted => 'Work completed';

  @override
  String get workflowProgressTitle => 'Workflow progress';

  @override
  String workflowProgressLabel(int completed, int total) =>
      '$completed of $total steps complete';

  @override
  String get currentStepLabel => 'Current step';

  @override
  String get jobNumberLabel => 'Job Number';

  @override
  String get customerLabel => 'Customer';

  @override
  String get assignedTechnicianLabel => 'Assigned Technician';

  @override
  String get jobTypeLabel => 'Job Category';

  @override
  String get jobCategoryHomeRenovation => 'Home Renovation';

  @override
  String get jobCategoryKitchenRenovation => 'Kitchen Renovation';

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
  @override
  String get jobInformationTitle => 'Job Information';

  @override
  String get customerInfoUnavailable =>
      'Customer information is not available for this job.';

  @override
  String get startJobButton => 'Start Job';

  @override
  String jobStartedAt(String time) => 'Started: $time';

  @override
  String get jobStartedMessage => 'Job started';

  @override
  String get startJobFailedMessage => 'Unable to start job';

  @override
  String get jobAlreadyStartedMessage => 'Job has already been started';

  @override
  String get beforePhotosTitle => 'Before Photos';

  @override
  String get addBeforePhotoButton => 'Add Before Photo';

  @override
  String get takePhotoButton => 'Take Photo';

  @override
  String get chooseFromGalleryButton => 'Choose from Gallery';

  @override
  String get noBeforePhotosYet => 'No before photos yet';

  @override
  String get beforePhotosRequiredHint =>
      'Photograph the site before you start — at least one before photo is required to complete the job.';

  @override
  String get uploadingLabel => 'Uploading';

  @override
  String get uploadFailedLabel => 'Upload failed';

  @override
  String get photoSyncedLabel => 'Synced';

  @override
  String get retryButton => 'Retry';

  @override
  String get cameraUnavailableError =>
      'The camera is not available on this device.';

  @override
  String get photoAccessDeniedError =>
      'Access to the camera or photo library was denied.';

  @override
  String get invalidImageError => 'The selected image could not be read.';

  @override
  String get addBeforePhotoFailedError => 'Unable to add the before photo.';

  // --- After Photos -------------------------------------------------------
  @override
  String get afterPhotosTitle => 'After Photos';

  @override
  String get addAfterPhotoButton => 'Add After Photo';

  @override
  String get noAfterPhotosYet => 'No after photos yet';

  @override
  String get afterPhotosRequiredHint =>
      'Photograph the finished work — at least one after photo is required to complete the job.';

  @override
  String get addAfterPhotoFailedError => 'Unable to add the after photo.';

  // --- Customer Signature ---------------------------------------------------
  @override
  String get customerSignatureTitle => 'Customer Signature';

  @override
  String get signatureHint => 'Customer signs here';

  @override
  String get clearButton => 'Clear';

  @override
  String get saveSignatureButton => 'Save Signature';

  @override
  String get signatureRequiredError => 'Signature required';

  @override
  String get signatureSavedMessage => 'Signature saved';

  @override
  String get signatureSaveFailedMessage => 'Failed to save signature';

  @override
  String get noSignatureYet => 'No signature yet';

  @override
  String get signatureHelper =>
      'The customer signs with a finger inside the box.';

  @override
  String get signatureConfirmsWorkHint =>
      'The signature confirms that the finished work is accepted.';

  @override
  String get replaceSignatureButton => 'Replace Signature';

  @override
  String stepLabel(int step) => 'Step $step';

  @override
  String get customerRequestLabel => 'Customer Request';

  @override
  String get workDescriptionSubtitle => 'Your report of the work performed';

  @override
  String jobCompletedAt(String time) => 'Completed on $time';

  // --- Work Description -------------------------------------------------------
  @override
  String get workDescriptionTitle => 'Work Description';

  @override
  String get workDescriptionHint => 'Describe the work performed';

  @override
  String get workDescriptionNoneYet => 'No work description yet.';

  @override
  String get workDescriptionRequiredHint =>
      'The work description is required to complete the job.';

  @override
  String get workDescriptionEmptyError => 'Work description cannot be empty.';

  @override
  String workDescriptionTooLongError(int max) =>
      'Work description is too long (maximum $max characters).';

  @override
  String get workDescriptionSavedMessage => 'Work description saved.';

  @override
  String get workDescriptionSaveFailedMessage =>
      'Failed to save work description.';

  @override
  String get workDescriptionSavingLabel => 'Saving…';

  @override
  String get completeJobButton => 'Complete Job';

  @override
  String get completionRequirementsTitle => 'Completion Requirements';

  @override
  String get requirementDoneLabel => 'Done';

  @override
  String get requirementOpenLabel => 'Open';

  @override
  String get jobCompletedMessage => 'Job completed';

  @override
  String get missingBeforePhotoError => 'Missing Before Photo';

  @override
  String get missingWorkDescriptionError => 'Missing Work Description';

  @override
  String get missingAfterPhotoError => 'Missing After Photo';

  @override
  String get missingSignatureError => 'Missing Customer Signature';

  @override
  String get internetRequiredToCompleteJob =>
      'Internet connection is required to complete the job.';

  @override
  String get unableToCompleteJobError => 'Unable to complete the job.';

  @override
  String get waitingForFileSync => 'Waiting for files to finish uploading…';

  @override
  String get jobsEmptyTitle => 'No jobs yet';

  @override
  String get jobsEmptySubtitle => 'New jobs will appear here.';

  @override
  String get createFirstJobButton => 'Create the first job';

  @override
  String get jobsErrorTitle => 'Something went wrong';

  @override
  String get jobsErrorSubtitle =>
      'Jobs could not be loaded. Please check your connection and try again.';

  @override
  String get jobsLoadingLabel => 'Loading jobs';

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
  String get searchJobsHint => 'Search by job number, customer, category or status';

  @override
  String get filterStatusLabel => 'Status';

  @override
  String get allStatusesLabel => 'All statuses';

  @override
  String get filterCategoryLabel => 'Category';

  @override
  String get allCategoriesLabel => 'All categories';

  @override
  String get clearFiltersButton => 'Clear filters';

  @override
  String get noJobsMatchTitle => 'No matching jobs';

  @override
  String get noJobsMatchSubtitle => 'Try a different search or clear the filters.';

  // --- Job creation (admin workflow) -----------------------------------------
  @override
  String get createJobButton => 'Create Job';

  @override
  String get createJobIntro => 'Choose a customer, job type and active technician.';

  @override
  String get createJobReviewTitle => 'Review job details';

  @override
  String get createJobOptionsFailedMessage =>
      'Options could not be loaded. Check your connection and try again.';

  @override
  String get createAndAssignJobButton => 'Create & Assign Job';

  @override
  String get selectCustomerLabel => 'Select Customer';

  @override
  String get selectTechnicianLabel => 'Select Technician';

  @override
  String get createJobSuccessMessage => 'Job created and assigned.';

  @override
  String get createJobFailedMessage =>
      'The job could not be created. Please try again.';

  @override
  String get noActiveTechniciansMessage =>
      'No active technicians are available.';

  // --- Customers -------------------------------------------------------------
  @override
  String get customersTitle => 'Customers';

  @override
  String get customerTitle => 'Customer';

  @override
  String get addCustomer => 'Add customer';

  @override
  String get editCustomer => 'Edit customer';

  @override
  String get deleteCustomer => 'Delete customer';

  @override
  String get customersSubtitle =>
      'Manage customer records and their contact details.';

  @override
  String get customersLoadingLabel => 'Loading customers';

  @override
  String customersCountLabel(int count) => count == 1
      ? '1 customer'
      : '$count customers';

  @override
  String get clearSearchButton => 'Clear search';

  @override
  String get customerBasicsGroup => 'Customer details';

  @override
  String get customerContactGroup => 'Contact information';

  @override
  String get customerAddressGroup => 'Site address';

  @override
  String get customerNotesGroup => 'Additional information';

  @override
  String get customerRequiredFieldsHint => 'Name and address are required.';

  @override
  String get customerNameHint => 'Full name';

  @override
  String get customerPhoneHint => 'Include the country code if available';

  @override
  String get customerEmailHint => 'name@example.com';

  @override
  String get customerAddressHint => 'Street and house number';

  @override
  String get customerCityHint => 'Town or city';

  @override
  String get customerPostalCodeHint => 'Postal or ZIP code';

  @override
  String get customerNotesHint => 'Access instructions or other useful context';

  @override
  String get searchCustomersHint => 'Search name, phone, email or address';

  @override
  String get customerNameLabel => 'Name';

  @override
  String get customerPhoneLabel => 'Phone';

  @override
  String get customerEmailLabel => 'Email';

  @override
  String get customerAddressLabel => 'Address';

  @override
  String get customerCityLabel => 'City';

  @override
  String get customerPostalCodeLabel => 'Postal code';

  @override
  String get customerNotesLabel => 'Notes';

  @override
  String get saveButton => 'Save';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get deleteButton => 'Delete';

  @override
  String get updatedAtLabel => 'Updated at';

  @override
  String get customersEmptyTitle => 'No customers';

  @override
  String get customersEmptySubtitle =>
      'Customers you add will appear here — even without an internet '
      'connection. Changes are sent to the server as soon as you are back '
      'online.';

  @override
  String get customersNoResultsTitle => 'No matching customers';

  @override
  String get customersErrorTitle => 'Customers could not be loaded';

  @override
  String get customersErrorSubtitle =>
      'The local copy could not be read. Please try again.';

  @override
  String get customerNotFoundTitle => 'Customer not found';

  @override
  String get customerNotFoundSubtitle =>
      'It may have been deleted on this device.';

  @override
  String get customerSaveFailed => 'The change could not be saved.';

  @override
  String get customerSavedSuccess => 'Customer saved successfully.';

  @override
  String get customerLinkedJobsError =>
      'This customer still has jobs linked to it and cannot be deleted.';

  @override
  String deleteCustomerConfirmation(String name) =>
      'This deletes "$name" from the app and, once you are online, from the '
      'server. Linked jobs are never deleted automatically.';

  @override
  String get offlineLabel => 'Offline';

  @override
  String get syncStatusTitle => 'Sync & connection';

  @override
  String get syncingLabel => 'Syncing…';

  @override
  String get pendingSyncLabel => 'Pending sync';

  @override
  String get syncedLabel => 'Synced';

  @override
  String get syncFailedLabel => 'Sync failed';

  @override
  String get validationRequiredField => 'This field is required.';

  // --- Admin management (technicians & customers) ---------------------------
  @override
  String get adminManagementTitle => "Administration";

  @override
  String get adminTechniciansTileSubtitle => "Block, unblock or delete technician accounts.";

  @override
  String get adminCustomersTileSubtitle => "Add, edit, block or delete customers.";

  @override
  String get adminTechniciansTitle => "Manage Technicians";

  @override
  String get adminTechniciansSubtitle => "Every technician account with its state, job history and management actions.";

  @override
  String get adminTechniciansLoadingLabel => "Loading technicians…";

  @override
  String get adminTechniciansEmptyTitle => "No technician accounts";

  @override
  String get adminTechniciansEmptySubtitle => "Technicians appear here as soon as they confirm their email and are provisioned automatically.";

  @override
  String get adminCustomersTitle => "Manage Customers";

  @override
  String get adminCustomersLoadingLabel => "Loading customers…";

  @override
  String get adminCustomersEmptyTitle => "No customers yet";

  @override
  String get adminCustomersEmptySubtitle => "Add the first customer to be able to create jobs.";

  @override
  String get adminCustomerDetailsTitle => "Customer details";

  @override
  String get adminLoadFailedTitle => "Could not load";

  @override
  String get adminStatusActive => "Active";

  @override
  String get adminStatusBlocked => "Blocked";

  @override
  String get adminStatusDeleted => "Deleted";

  @override
  String get adminStatusUnknown => "Unknown";

  @override
  String get adminBlockAction => "Block";

  @override
  String get adminUnblockAction => "Unblock";

  @override
  String get adminSoftDeleteAction => "Delete";

  @override
  String get adminConfirmAction => "Confirm";

  @override
  String get adminHistoryKeptNotice => "Jobs, photos and signatures already recorded are kept — nothing is deleted.";

  @override
  String get adminDeletedTechnicianNotice => "This technician is deleted. Jobs, photos and signatures stay recorded, and the account cannot be reactivated.";
  @override
  String get adminDeletedCustomerNotice => "This customer is deleted. Its history stays readable, and it cannot be edited or reactivated.";

  @override
  String get adminOwnAccountNotice => "This is your own account — you cannot change its status.";

  @override
  String get adminAdministratorNotice => "Administrator account — technician management does not apply to it.";

  @override
  String adminAccountsCountLabel(int count) => '$count accounts';

  @override
  String adminAssignedJobsLabel(int count) => '$count assigned';

  @override
  String adminCompletedJobsLabel(int count) => '$count completed';

  @override
  String adminCustomerJobsCountLabel(int count) => '$count jobs';

  @override
  String adminBlockedOnLabel(String date) => 'Blocked on $date';

  @override
  String adminDeletedOnLabel(String date) => 'Deleted on $date';

  @override
  String get adminBlockTechnicianConfirmTitle => "Block technician?";

  @override
  String adminBlockTechnicianConfirmBody(String name) => '“$name” loses access immediately: no job can be started, no photo uploaded and no existing data read. The app signs the account out on the next start.';

  @override
  String get adminUnblockTechnicianConfirmTitle => "Unblock technician?";

  @override
  String adminUnblockTechnicianConfirmBody(String name) => '“$name” regains access to assigned jobs, photos and signatures.';

  @override
  String get adminDeleteTechnicianConfirmTitle => "Delete technician?";

  @override
  String adminDeleteTechnicianConfirmBody(String name) => '“$name” is removed from the management lists (logical deletion). The auth account and the employee row are kept, historical jobs stay assigned to the name, and the account cannot be reactivated.';

  @override
  String get adminBlockCustomerConfirmTitle => "Block customer?";

  @override
  String adminBlockCustomerConfirmBody(String name) => '“$name” can no longer be selected for new jobs. Existing jobs, photos and signatures stay viewable.';

  @override
  String get adminUnblockCustomerConfirmTitle => "Unblock customer?";

  @override
  String adminUnblockCustomerConfirmBody(String name) => '“$name” can be selected for new jobs again immediately.';

  @override
  String get adminDeleteCustomerConfirmTitle => "Delete customer?";

  @override
  String adminDeleteCustomerConfirmBody(String name) => '“$name” is logically deleted and can no longer be selected or edited. Job and file history is preserved.';

  @override
  String get adminTechnicianBlockedMessage => "Technician blocked.";

  @override
  String get adminTechnicianUnblockedMessage => "Technician unblocked.";

  @override
  String get adminTechnicianDeletedMessage => "Technician deleted (history preserved).";

  @override
  String get adminCustomerBlockedMessage => "Customer blocked.";

  @override
  String get adminCustomerUnblockedMessage => "Customer unblocked.";

  @override
  String get adminCustomerDeletedMessage => "Customer deleted (history preserved).";

  @override
  String get adminCustomerCreatedMessage => "Customer created.";

  @override
  String get adminCustomerUpdatedMessage => "Customer updated.";

  @override
  String get adminErrorNotAuthorized => "Only an administrator may manage technicians and customers.";

  @override
  String get adminErrorNotFound => "The record no longer exists on the server.";

  @override
  String get adminErrorRecordDeleted => "The record is deleted and can no longer be changed.";

  @override
  String get adminErrorInvalidInput => "The server rejected the values. Please check the form.";

  @override
  String get adminErrorCustomerBlocked => "This customer is blocked or deleted and cannot be used for a new job.";

  @override
  String get adminErrorNetwork => "No connection to the server. Please try again.";

  @override
  String get adminErrorUnknown => "The action failed. Please try again.";

  // --- Technician: create customer & job -----------------------------------

  @override
  String get technicianCreateJobTitle => 'Create Customer & Job';

  @override
  String get technicianCreateJobSubtitle =>
      'Register a customer on site and create their job in one step. The job '
      'is always assigned to you.';

  @override
  String get technicianCreateJobButton => 'Create Customer & Job';

  @override
  String get technicianCreateJobEntryTitle => 'New customer & job';

  @override
  String get technicianCreateJobEntrySubtitle =>
      'Register a customer and create their job.';

  @override
  String get technicianJobCustomerSection => 'Customer';

  @override
  String get technicianJobDetailsSection => 'Job details';

  @override
  String get technicianJobCustomerModeNew => 'New customer';

  @override
  String get technicianJobCustomerModeExisting => 'Existing customer';

  @override
  String get technicianSelectExistingCustomerTitle =>
      'Select a customer you work for';

  @override
  String get technicianAccessibleCustomersEmptySubtitle =>
      'You can create a job for a customer you already work for. For anybody '
      'else, register a new customer.';

  @override
  String get technicianAccessibleCustomersError =>
      'Your customers could not be loaded. You can still register a new '
      'customer.';

  @override
  String get technicianJobDescriptionHint => 'What the customer asked for';

  @override
  String get technicianJobAssignedToLabel => 'Assigned technician';

  @override
  String get technicianJobAssignedToHint =>
      'Jobs you create are always assigned to you.';

  @override
  String technicianCreateJobSuccess(int jobNumber) =>
      'Job #$jobNumber created.';

  @override
  String get technicianCreateJobQueued =>
      'Saved on this device — it will be sent to the server as soon as you '
      'are online.';

  @override
  String get technicianCreateJobFailed =>
      'The job could not be created. Please try again.';

  @override
  String get technicianCreateJobErrorUnauthorized =>
      'You are not allowed to create this job.';

  @override
  String get technicianCreateJobErrorCustomerNotFound =>
      'This customer no longer exists.';

  @override
  String get technicianCreateJobErrorCustomerBlocked =>
      'This customer is blocked or deleted and cannot receive a new job.';

  @override
  String get technicianCreateJobErrorInvalidInput =>
      'Please check the form and try again.';

  @override
  String get technicianCreateJobErrorNotAuthenticated =>
      'Your session has expired. Please sign in again.';

  @override
  String get technicianCreateJobErrorUnknown =>
      'The server refused the request. Please try again.';

  @override
  String validationFieldTooLong(int count) =>
      'Use at most $count characters.';

  @override
  String get validationPhoneInvalid => 'Please enter a valid phone number.';

  @override
  String get accountSettingsTooltip =>
      'Account & settings';

  @override
  String get recentJobsTitle =>
      'Recent jobs';

  @override
  String get recentJobsSubtitle =>
      'The most recently updated jobs.';

  @override
  String get recentJobsViewAll =>
      'View all';

  @override
  String get unassignedLabel =>
      'Unassigned';

  @override
  String get adminOverviewSubtitle =>
      'Every job in the system, by state.';

  @override
  String get technicianOverviewSubtitle =>
      'Your own jobs, by state.';

  @override
  String get dashboardOverviewErrorTitle =>
      'Overview unavailable';

  @override
  String get dashboardOverviewErrorMessage =>
      'The job figures could not be loaded. Retry to refresh them.';
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
  String get loginWelcomeTitle => 'Willkommen zurück';

  @override
  String get loginWelcomeSubtitle =>
      'Melden Sie sich an, um in Ihrem Arbeitsbereich weiterzuarbeiten.';

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
  String get passwordReqSpecialChar => 'Mindestens ein Sonderzeichen (!@#...)';

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
  String get pageNotFoundSubtitle =>
      'Dieser Link führt ins Leere. Er ist möglicherweise veraltet oder '
      'unvollständig.';

  @override
  String get pageNotFoundAction => 'Zur Startseite';

  @override
  String get viewJobsButton => 'Aufträge anzeigen';

  @override
  String get viewCustomersButton => 'Kunden anzeigen';

  @override
  String welcomeNameLabel(String name) => 'Willkommen, $name';

  @override
  String get roleAdminLabel => 'Administrator';

  @override
  String get roleTechnicianLabel => 'Techniker';

  @override
  String get accountTitle => 'Konto';

  @override
  String get homeTabLabel => 'Start';

  @override
  String get kitchenTabLabel => 'Küche';

  @override
  String get homeRenovationTabLabel => 'Haussanierung';

  @override
  String get overviewTitle => 'Übersicht';

  @override
  String get totalJobsLabel => 'Gesamt';

  @override
  String get quickActionsTitle => 'Schnellzugriff';

  @override
  String get categoriesTitle => 'Kategorien';

  @override
  String jobsCountLabel(int count) =>
      count == 1 ? '1 Auftrag' : '$count Aufträge';

  @override
  String get continueJobButton => 'Auftrag fortsetzen';

  @override
  String get currentJobTitle => 'Aktueller Auftrag';

  @override
  String get noAssignedJobsTitle => 'Keine zugewiesenen Aufträge';

  @override
  String get noAssignedJobsSubtitle =>
      'Neue Aufträge, die Ihnen zugewiesen werden, erscheinen hier.';

  @override
  String nextActionLabel(String action) => 'Als Nächstes: $action';

  @override
  String get jobsTitle => 'Aufträge';

  @override
  String get myJobsTitle => 'Meine Aufträge';

  @override
  String get jobDetailsTitle => 'Auftragsdetails';

  @override
  String get jobActivityTitle => 'Verlauf';
  @override
  String get activityAssigned => 'Auftrag zugewiesen';
  @override
  String get activityStarted => 'Arbeit begonnen';
  @override
  String get activityBeforePhoto => 'Vorher-Foto aufgenommen';
  @override
  String get activityAfterPhoto => 'Nachher-Foto aufgenommen';
  @override
  String get activitySignature => 'Unterschrift aufgenommen';
  @override
  String get activityCompleted => 'Arbeit abgeschlossen';

  @override
  String get workflowProgressTitle => 'Arbeitsfortschritt';

  @override
  String workflowProgressLabel(int completed, int total) =>
      '$completed von $total Schritten abgeschlossen';

  @override
  String get currentStepLabel => 'Aktueller Schritt';

  @override
  String get jobNumberLabel => 'Auftragsnummer';

  @override
  String get customerLabel => 'Kunde';

  @override
  String get assignedTechnicianLabel => 'Zugewiesener Techniker';

  @override
  String get jobTypeLabel => 'Jobkategorie';

  @override
  String get jobCategoryHomeRenovation => 'Hausrenovierung';

  @override
  String get jobCategoryKitchenRenovation => 'Küchenrenovierung';

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
  @override
  String get jobInformationTitle => 'Auftragsinformationen';

  @override
  String get customerInfoUnavailable =>
      'Für diesen Auftrag sind keine Kundeninformationen verfügbar.';

  @override
  String get startJobButton => 'Auftrag starten';

  @override
  String jobStartedAt(String time) => 'Gestartet: $time';

  @override
  String get jobStartedMessage => 'Auftrag gestartet';

  @override
  String get startJobFailedMessage => 'Auftrag konnte nicht gestartet werden';

  @override
  String get jobAlreadyStartedMessage => 'Auftrag wurde bereits gestartet';

  @override
  String get beforePhotosTitle => 'Vorher-Fotos';

  @override
  String get addBeforePhotoButton => 'Vorher-Foto hinzufügen';

  @override
  String get takePhotoButton => 'Foto aufnehmen';

  @override
  String get chooseFromGalleryButton => 'Aus Galerie auswählen';

  @override
  String get noBeforePhotosYet => 'Noch keine Vorher-Fotos';

  @override
  String get beforePhotosRequiredHint =>
      'Fotografieren Sie die Baustelle vor Arbeitsbeginn — mindestens ein Vorher-Foto ist zum Abschließen des Auftrags erforderlich.';

  @override
  String get uploadingLabel => 'Wird hochgeladen';

  @override
  String get uploadFailedLabel => 'Upload fehlgeschlagen';

  @override
  String get photoSyncedLabel => 'Synchronisiert';

  @override
  String get retryButton => 'Erneut versuchen';

  @override
  String get cameraUnavailableError =>
      'Die Kamera ist auf diesem Gerät nicht verfügbar.';

  @override
  String get photoAccessDeniedError =>
      'Der Zugriff auf Kamera oder Fotobibliothek wurde verweigert.';

  @override
  String get invalidImageError =>
      'Das ausgewählte Bild konnte nicht gelesen werden.';

  @override
  String get addBeforePhotoFailedError =>
      'Das Vorher-Foto konnte nicht hinzugefügt werden.';

  // --- After Photos -------------------------------------------------------
  @override
  String get afterPhotosTitle => 'Nachher-Fotos';

  @override
  String get addAfterPhotoButton => 'Nachher-Foto hinzufügen';

  @override
  String get noAfterPhotosYet => 'Noch keine Nachher-Fotos';

  @override
  String get afterPhotosRequiredHint =>
      'Fotografieren Sie die fertige Arbeit — mindestens ein Nachher-Foto ist zum Abschließen des Auftrags erforderlich.';

  @override
  String get addAfterPhotoFailedError =>
      'Das Nachher-Foto konnte nicht hinzugefügt werden.';

  // --- Customer Signature ---------------------------------------------------
  @override
  String get customerSignatureTitle => 'Kundensignatur';

  @override
  String get signatureHint => 'Der Kunde unterschreibt hier';

  @override
  String get clearButton => 'Löschen';

  @override
  String get saveSignatureButton => 'Unterschrift speichern';

  @override
  String get signatureRequiredError => 'Unterschrift erforderlich';

  @override
  String get signatureSavedMessage => 'Unterschrift gespeichert';

  @override
  String get signatureSaveFailedMessage =>
      'Unterschrift konnte nicht gespeichert werden.';

  @override
  String get noSignatureYet => 'Noch keine Unterschrift vorhanden';

  @override
  String get signatureHelper =>
      'Der Kunde unterschreibt mit dem Finger im Feld.';

  @override
  String get signatureConfirmsWorkHint =>
      'Mit der Unterschrift bestätigt der Kunde die fertiggestellte Arbeit.';

  @override
  String get replaceSignatureButton => 'Unterschrift ersetzen';

  @override
  String stepLabel(int step) => 'Schritt $step';

  @override
  String get customerRequestLabel => 'Kundenanfrage';

  @override
  String get workDescriptionSubtitle =>
      'Ihr Bericht über die ausgeführten Arbeiten';

  @override
  String jobCompletedAt(String time) => 'Abgeschlossen am $time';

  // --- Work Description -------------------------------------------------------
  @override
  String get workDescriptionTitle => 'Arbeitsbeschreibung';

  @override
  String get workDescriptionHint => 'Beschreiben Sie die ausgeführten Arbeiten';

  @override
  String get workDescriptionNoneYet =>
      'Noch keine Arbeitsbeschreibung vorhanden.';

  @override
  String get workDescriptionRequiredHint =>
      'Die Arbeitsbeschreibung ist zum Abschließen des Auftrags erforderlich.';

  @override
  String get workDescriptionEmptyError =>
      'Die Arbeitsbeschreibung darf nicht leer sein.';

  @override
  String workDescriptionTooLongError(int max) =>
      'Die Arbeitsbeschreibung ist zu lang (maximal $max Zeichen).';

  @override
  String get workDescriptionSavedMessage => 'Arbeitsbeschreibung gespeichert.';

  @override
  String get workDescriptionSaveFailedMessage =>
      'Die Arbeitsbeschreibung konnte nicht gespeichert werden.';

  @override
  String get workDescriptionSavingLabel => 'Speichern…';

  @override
  String get completeJobButton => 'Auftrag abschließen';

  @override
  String get completionRequirementsTitle => 'Abschlussvoraussetzungen';

  @override
  String get requirementDoneLabel => 'Erledigt';

  @override
  String get requirementOpenLabel => 'Offen';

  @override
  String get jobCompletedMessage => 'Auftrag abgeschlossen';

  @override
  String get missingBeforePhotoError => 'Vorher-Foto fehlt';

  @override
  String get missingWorkDescriptionError => 'Arbeitsbeschreibung fehlt';

  @override
  String get missingAfterPhotoError => 'Nachher-Foto fehlt';

  @override
  String get missingSignatureError => 'Kundenunterschrift fehlt';

  @override
  String get internetRequiredToCompleteJob =>
      'Zum Abschließen des Auftrags ist eine Internetverbindung erforderlich.';

  @override
  String get unableToCompleteJobError =>
      'Der Auftrag konnte nicht abgeschlossen werden.';

  @override
  String get waitingForFileSync =>
      'Warten, bis alle Dateien hochgeladen wurden…';

  @override
  String get jobsEmptyTitle => 'Noch keine Aufträge';

  @override
  String get jobsEmptySubtitle => 'Neue Aufträge erscheinen hier.';

  @override
  String get createFirstJobButton => 'Ersten Auftrag anlegen';

  @override
  String get jobsErrorTitle => 'Etwas ist schiefgelaufen';

  @override
  String get jobsErrorSubtitle =>
      'Aufträge konnten nicht geladen werden. Bitte prüfen Sie Ihre Verbindung und versuchen Sie es erneut.';

  @override
  String get jobsLoadingLabel => 'Aufträge werden geladen';

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
  String get searchJobsHint => 'Nach Auftragsnummer, Kunde, Kategorie oder Status suchen';

  @override
  String get filterStatusLabel => 'Status';

  @override
  String get allStatusesLabel => 'Alle Status';

  @override
  String get filterCategoryLabel => 'Kategorie';

  @override
  String get allCategoriesLabel => 'Alle Kategorien';

  @override
  String get clearFiltersButton => 'Filter zurücksetzen';

  @override
  String get noJobsMatchTitle => 'Keine passenden Aufträge';

  @override
  String get noJobsMatchSubtitle => 'Ändern Sie die Suche oder setzen Sie die Filter zurück.';

  // --- Job creation (admin workflow) -----------------------------------------
  @override
  String get createJobButton => 'Auftrag erstellen';

  @override
  String get createJobIntro =>
      'Wählen Sie einen Kunden, einen Auftragstyp und einen aktiven Techniker.';

  @override
  String get createJobReviewTitle => 'Auftragsdetails überprüfen';

  @override
  String get createJobOptionsFailedMessage =>
      'Die Auswahl konnte nicht geladen werden. Prüfen Sie Ihre Verbindung und versuchen Sie es erneut.';

  @override
  String get createAndAssignJobButton => 'Auftrag erstellen & zuweisen';

  @override
  String get selectCustomerLabel => 'Kunde auswählen';

  @override
  String get selectTechnicianLabel => 'Techniker auswählen';

  @override
  String get createJobSuccessMessage => 'Auftrag erstellt und zugewiesen.';

  @override
  String get createJobFailedMessage =>
      'Der Auftrag konnte nicht erstellt werden. Bitte versuche es erneut.';

  @override
  String get noActiveTechniciansMessage => 'Keine aktiven Techniker verfügbar.';

  // --- Customers -------------------------------------------------------------
  @override
  String get customersTitle => 'Kunden';

  @override
  String get customerTitle => 'Kunde';

  @override
  String get addCustomer => 'Kunde hinzufügen';

  @override
  String get editCustomer => 'Kunden bearbeiten';

  @override
  String get deleteCustomer => 'Kunden löschen';

  @override
  String get customersSubtitle => 'Kundenstammdaten und Kontaktdaten verwalten.';

  @override
  String get customersLoadingLabel => 'Kunden werden geladen';

  @override
  String customersCountLabel(int count) => count == 1
      ? '1 Kunde'
      : '$count Kunden';

  @override
  String get clearSearchButton => 'Suche löschen';

  @override
  String get customerBasicsGroup => 'Kundendaten';

  @override
  String get customerContactGroup => 'Kontaktinformationen';

  @override
  String get customerAddressGroup => 'Einsatzadresse';

  @override
  String get customerNotesGroup => 'Weitere Hinweise';

  @override
  String get customerRequiredFieldsHint => 'Name und Adresse sind Pflichtfelder.';

  @override
  String get customerNameHint => 'Vollständiger Name';

  @override
  String get customerPhoneHint => 'Wenn möglich mit Ländervorwahl';

  @override
  String get customerEmailHint => 'name@beispiel.de';

  @override
  String get customerAddressHint => 'Straße und Hausnummer';

  @override
  String get customerCityHint => 'Ort oder Stadt';

  @override
  String get customerPostalCodeHint => 'Postleitzahl';

  @override
  String get customerNotesHint => 'Zugangshinweise oder sonstige wichtige Informationen';

  @override
  String get searchCustomersHint => 'Name, Telefon, E-Mail oder Adresse suchen';

  @override
  String get customerNameLabel => 'Name';

  @override
  String get customerPhoneLabel => 'Telefon';

  @override
  String get customerEmailLabel => 'E-Mail';

  @override
  String get customerAddressLabel => 'Adresse';

  @override
  String get customerCityLabel => 'Stadt';

  @override
  String get customerPostalCodeLabel => 'PLZ';

  @override
  String get customerNotesLabel => 'Anmerkungen';

  @override
  String get saveButton => 'Speichern';

  @override
  String get cancelButton => 'Abbrechen';

  @override
  String get deleteButton => 'Löschen';

  @override
  String get updatedAtLabel => 'Aktualisiert am';

  @override
  String get customersEmptyTitle => 'Keine Kunden';

  @override
  String get customersEmptySubtitle =>
      'Hinzugefügte Kunden erscheinen hier – auch ohne Internetverbindung. '
      'Änderungen werden gesendet, sobald Sie wieder online sind.';

  @override
  String get customersNoResultsTitle => 'Keine passenden Kunden';

  @override
  String get customersErrorTitle => 'Kunden konnten nicht geladen werden';

  @override
  String get customersErrorSubtitle =>
      'Die lokale Kopie konnte nicht gelesen werden. Bitte erneut versuchen.';

  @override
  String get customerNotFoundTitle => 'Kunde nicht gefunden';

  @override
  String get customerNotFoundSubtitle =>
      'Er wurde möglicherweise auf diesem Gerät gelöscht.';

  @override
  String get customerSaveFailed =>
      'Die Änderung konnte nicht gespeichert werden.';

  @override
  String get customerSavedSuccess => 'Kunde erfolgreich gespeichert.';

  @override
  String get customerLinkedJobsError =>
      'Für diesen Kunden existieren noch Aufträge. Er kann nicht gelöscht '
      'werden.';

  @override
  String deleteCustomerConfirmation(String name) =>
      'Dadurch wird „$name“ aus der App und nach der nächsten Verbindung '
      'auch vom Server gelöscht. Verknüpfte Aufträge werden niemals '
      'automatisch gelöscht.';

  @override
  String get offlineLabel => 'Offline';

  @override
  String get syncStatusTitle => 'Synchronisierung & Verbindung';

  @override
  String get syncingLabel => 'Synchronisiere…';

  @override
  String get pendingSyncLabel => 'Synchronisierung ausstehend';

  @override
  String get syncedLabel => 'Synchronisiert';

  @override
  String get syncFailedLabel => 'Sync fehlgeschlagen';

  @override
  String get validationRequiredField => 'Pflichtfeld.';

  // --- Admin management (technicians & customers) ---------------------------
  @override
  String get adminManagementTitle => "Verwaltung";

  @override
  String get adminTechniciansTileSubtitle => "Techniker-Konten sperren, entsperren oder löschen.";

  @override
  String get adminCustomersTileSubtitle => "Kunden anlegen, bearbeiten, sperren oder löschen.";

  @override
  String get adminTechniciansTitle => "Techniker verwalten";

  @override
  String get adminTechniciansSubtitle => "Alle Techniker-Konten mit Status, Auftragshistorie und Verwaltungsaktionen.";

  @override
  String get adminTechniciansLoadingLabel => "Techniker werden geladen…";

  @override
  String get adminTechniciansEmptyTitle => "Keine Techniker-Konten";

  @override
  String get adminTechniciansEmptySubtitle => "Techniker erscheinen hier, sobald sie ihre E-Mail bestätigt haben und automatisch angelegt wurden.";

  @override
  String get adminCustomersTitle => "Kunden verwalten";

  @override
  String get adminCustomersLoadingLabel => "Kunden werden geladen…";

  @override
  String get adminCustomersEmptyTitle => "Noch keine Kunden";

  @override
  String get adminCustomersEmptySubtitle => "Legen Sie den ersten Kunden an, um Aufträge erstellen zu können.";

  @override
  String get adminCustomerDetailsTitle => "Kundendetails";

  @override
  String get adminLoadFailedTitle => "Laden fehlgeschlagen";

  @override
  String get adminStatusActive => "Aktiv";

  @override
  String get adminStatusBlocked => "Gesperrt";

  @override
  String get adminStatusDeleted => "Gelöscht";

  @override
  String get adminStatusUnknown => "Unbekannt";

  @override
  String get adminBlockAction => "Sperren";

  @override
  String get adminUnblockAction => "Entsperren";

  @override
  String get adminSoftDeleteAction => "Löschen";

  @override
  String get adminConfirmAction => "Bestätigen";

  @override
  String get adminHistoryKeptNotice => "Bereits erfasste Aufträge, Fotos und Unterschriften bleiben erhalten — es wird nichts gelöscht.";

  @override
  String get adminDeletedTechnicianNotice => "Dieser Techniker ist gelöscht. Aufträge, Fotos und Unterschriften bleiben erhalten; eine Reaktivierung ist nicht möglich.";
  @override
  String get adminDeletedCustomerNotice => "Dieser Kunde ist gelöscht. Die Historie bleibt lesbar; bearbeiten oder reaktivieren ist nicht möglich.";

  @override
  String get adminOwnAccountNotice => "Das ist Ihr eigenes Konto — der Status kann nicht geändert werden.";

  @override
  String get adminAdministratorNotice => "Administrator-Konto — die Technikerverwaltung greift hier nicht.";

  @override
  String adminAccountsCountLabel(int count) => '$count Konten';

  @override
  String adminAssignedJobsLabel(int count) => '$count zugewiesen';

  @override
  String adminCompletedJobsLabel(int count) => '$count abgeschlossen';

  @override
  String adminCustomerJobsCountLabel(int count) => '$count Aufträge';

  @override
  String adminBlockedOnLabel(String date) => 'Gesperrt am $date';

  @override
  String adminDeletedOnLabel(String date) => 'Gelöscht am $date';

  @override
  String get adminBlockTechnicianConfirmTitle => "Techniker sperren?";

  @override
  String adminBlockTechnicianConfirmBody(String name) => '„$name“ verliert sofort den Zugriff: Es kann kein Auftrag gestartet, kein Foto hochgeladen und keine bestehenden Daten mehr gelesen werden. Beim nächsten Start wird das Konto abgemeldet.';

  @override
  String get adminUnblockTechnicianConfirmTitle => "Techniker entsperren?";

  @override
  String adminUnblockTechnicianConfirmBody(String name) => '„$name“ erhält wieder Zugriff auf zugewiesene Aufträge, Fotos und Unterschriften.';

  @override
  String get adminDeleteTechnicianConfirmTitle => "Techniker löschen?";

  @override
  String adminDeleteTechnicianConfirmBody(String name) => '„$name“ wird aus den Verwaltungslisten entfernt (logisches Löschen). Das Auth-Konto und der Mitarbeitereintrag bleiben erhalten, historische Aufträge bleiben dem Namen zugeordnet; eine Reaktivierung ist nicht möglich.';

  @override
  String get adminBlockCustomerConfirmTitle => "Kunden sperren?";

  @override
  String adminBlockCustomerConfirmBody(String name) => '„$name“ kann für neue Aufträge nicht mehr ausgewählt werden. Bestehende Aufträge, Fotos und Unterschriften bleiben einsehbar.';

  @override
  String get adminUnblockCustomerConfirmTitle => "Kunden entsperren?";

  @override
  String adminUnblockCustomerConfirmBody(String name) => '„$name“ kann sofort wieder für neue Aufträge ausgewählt werden.';

  @override
  String get adminDeleteCustomerConfirmTitle => "Kunden löschen?";

  @override
  String adminDeleteCustomerConfirmBody(String name) => '„$name“ wird logisch gelöscht und kann nicht mehr ausgewählt oder bearbeitet werden. Auftrags- und Dateihistorie bleibt erhalten.';

  @override
  String get adminTechnicianBlockedMessage => "Techniker gesperrt.";

  @override
  String get adminTechnicianUnblockedMessage => "Techniker entsperrt.";

  @override
  String get adminTechnicianDeletedMessage => "Techniker gelöscht (Historie bleibt erhalten).";

  @override
  String get adminCustomerBlockedMessage => "Kunde gesperrt.";

  @override
  String get adminCustomerUnblockedMessage => "Kunde entsperrt.";

  @override
  String get adminCustomerDeletedMessage => "Kunde gelöscht (Historie bleibt erhalten).";

  @override
  String get adminCustomerCreatedMessage => "Kunde angelegt.";

  @override
  String get adminCustomerUpdatedMessage => "Kunde aktualisiert.";

  @override
  String get adminErrorNotAuthorized => "Nur ein Administrator darf Techniker und Kunden verwalten.";

  @override
  String get adminErrorNotFound => "Der Datensatz existiert auf dem Server nicht mehr.";

  @override
  String get adminErrorRecordDeleted => "Der Datensatz ist gelöscht und kann nicht mehr geändert werden.";

  @override
  String get adminErrorInvalidInput => "Der Server hat die Eingaben abgelehnt. Bitte prüfen Sie das Formular.";

  @override
  String get adminErrorCustomerBlocked => "Dieser Kunde ist gesperrt oder gelöscht und kann für einen neuen Auftrag nicht verwendet werden.";

  @override
  String get adminErrorNetwork => "Keine Verbindung zum Server. Bitte erneut versuchen.";

  @override
  String get adminErrorUnknown => "Die Aktion ist fehlgeschlagen. Bitte erneut versuchen.";

  // --- Technician: create customer & job -----------------------------------

  @override
  String get technicianCreateJobTitle => 'Kunde & Auftrag anlegen';

  @override
  String get technicianCreateJobSubtitle =>
      'Erfasse einen Kunden vor Ort und lege seinen Auftrag in einem Schritt '
      'an. Der Auftrag wird immer dir zugewiesen.';

  @override
  String get technicianCreateJobButton => 'Kunde & Auftrag anlegen';

  @override
  String get technicianCreateJobEntryTitle => 'Neuer Kunde & Auftrag';

  @override
  String get technicianCreateJobEntrySubtitle =>
      'Kunden erfassen und Auftrag anlegen.';

  @override
  String get technicianJobCustomerSection => 'Kunde';

  @override
  String get technicianJobDetailsSection => 'Auftragsdaten';

  @override
  String get technicianJobCustomerModeNew => 'Neuer Kunde';

  @override
  String get technicianJobCustomerModeExisting => 'Bestehender Kunde';

  @override
  String get technicianSelectExistingCustomerTitle =>
      'Wähle einen Kunden, für den du arbeitest';

  @override
  String get technicianAccessibleCustomersEmptySubtitle =>
      'Du kannst einen Auftrag für Kunden anlegen, für die du bereits '
      'arbeitest. Für alle anderen erfasse bitte einen neuen Kunden.';

  @override
  String get technicianAccessibleCustomersError =>
      'Deine Kunden konnten nicht geladen werden. Du kannst trotzdem einen '
      'neuen Kunden erfassen.';

  @override
  String get technicianJobDescriptionHint => 'Was der Kunde benötigt';

  @override
  String get technicianJobAssignedToLabel => 'Zugewiesener Techniker';

  @override
  String get technicianJobAssignedToHint =>
      'Aufträge, die du anlegst, werden immer dir zugewiesen.';

  @override
  String technicianCreateJobSuccess(int jobNumber) =>
      'Auftrag #$jobNumber erstellt.';

  @override
  String get technicianCreateJobQueued =>
      'Auf diesem Gerät gespeichert — die Übertragung an den Server erfolgt, '
      'sobald du online bist.';

  @override
  String get technicianCreateJobFailed =>
      'Der Auftrag konnte nicht angelegt werden. Bitte erneut versuchen.';

  @override
  String get technicianCreateJobErrorUnauthorized =>
      'Du darfst diesen Auftrag nicht anlegen.';

  @override
  String get technicianCreateJobErrorCustomerNotFound =>
      'Dieser Kunde existiert nicht mehr.';

  @override
  String get technicianCreateJobErrorCustomerBlocked =>
      'Dieser Kunde ist gesperrt oder gelöscht und kann keinen neuen Auftrag '
      'erhalten.';

  @override
  String get technicianCreateJobErrorInvalidInput =>
      'Bitte prüfe das Formular und versuche es erneut.';

  @override
  String get technicianCreateJobErrorNotAuthenticated =>
      'Deine Sitzung ist abgelaufen. Bitte melde dich erneut an.';

  @override
  String get technicianCreateJobErrorUnknown =>
      'Der Server hat die Anfrage abgelehnt. Bitte erneut versuchen.';

  @override
  String validationFieldTooLong(int count) =>
      'Verwende höchstens $count Zeichen.';

  @override
  String get validationPhoneInvalid =>
      'Bitte gib eine gültige Telefonnummer ein.';

  @override
  String get accountSettingsTooltip =>
      'Konto & Einstellungen';

  @override
  String get recentJobsTitle =>
      'Letzte Aufträge';

  @override
  String get recentJobsSubtitle =>
      'Die zuletzt aktualisierten Aufträge.';

  @override
  String get recentJobsViewAll =>
      'Alle anzeigen';

  @override
  String get unassignedLabel =>
      'Nicht zugewiesen';

  @override
  String get adminOverviewSubtitle =>
      'Alle Aufträge im System, nach Status.';

  @override
  String get technicianOverviewSubtitle =>
      'Deine eigenen Aufträge, nach Status.';

  @override
  String get dashboardOverviewErrorTitle =>
      'Übersicht nicht verfügbar';

  @override
  String get dashboardOverviewErrorMessage =>
      'Die Auftragszahlen konnten nicht geladen werden. Versuche es erneut.';
}

/// Ergonomic shorthand on [BuildContext] for localized strings.
extension AppLocalizationsContextX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
