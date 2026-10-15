import 'package:equatable/equatable.dart';
import 'package:field_service/features/authentication/domain/entities/account_deletion_failure.dart';
import 'package:field_service/features/authentication/domain/entities/account_deletion_preview.dart';

/// Presentation-only state for the two-step backend account-deletion workflow.
///
/// A non-destructive preview must complete before a confirmation request can be
/// sent. Any failure preserves the authenticated session unless its JWT is no
/// longer valid, in which case the account page sends the user back to sign in.
enum AccountDeletionStatus {
  initial,
  previewing,
  previewReady,
  confirming,
  success,
  failure,
}

class AccountDeletionState extends Equatable {
  const AccountDeletionState({
    this.status = AccountDeletionStatus.initial,
    this.preview,
    this.failure,
  });

  final AccountDeletionStatus status;
  final AccountDeletionPreview? preview;
  final AccountDeletionFailureKind? failure;

  bool get isPreviewing => status == AccountDeletionStatus.previewing;

  bool get isConfirming => status == AccountDeletionStatus.confirming;

  bool get isBusy => isPreviewing || isConfirming;

  bool get isPreviewReady =>
      status == AccountDeletionStatus.previewReady && preview != null;

  bool get isSuccessful => status == AccountDeletionStatus.success;

  bool get hasFailed => status == AccountDeletionStatus.failure;

  @override
  List<Object?> get props => <Object?>[status, preview, failure];
}
