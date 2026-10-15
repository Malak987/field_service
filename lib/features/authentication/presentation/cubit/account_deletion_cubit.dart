import 'package:field_service/core/utils/logger.dart';
import 'package:field_service/features/authentication/domain/entities/account_deletion_failure.dart';
import 'package:field_service/features/authentication/domain/entities/account_deletion_preview.dart';
import 'package:field_service/features/authentication/domain/usecases/request_account_deletion.dart';
import 'package:field_service/features/authentication/presentation/cubit/account_deletion_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Owns the explicit preview/confirmation sequence for account deletion.
///
/// The preview call never deletes data. Confirmation is unavailable until a
/// preview succeeded, and this cubit never changes local data or auth state.
/// The account page clears the local session only after confirmation succeeds.
class AccountDeletionCubit extends Cubit<AccountDeletionState> {
  AccountDeletionCubit({
    required RequestAccountDeletion requestAccountDeletion,
  }) : _requestAccountDeletion = requestAccountDeletion,
       super(const AccountDeletionState());

  final RequestAccountDeletion _requestAccountDeletion;

  Future<void> previewDeletion() async {
    if (isClosed || state.isBusy || state.isSuccessful) {
      return;
    }

    emit(const AccountDeletionState(status: AccountDeletionStatus.previewing));

    try {
      final AccountDeletionPreview preview = await _requestAccountDeletion
          .preview();
      if (!isClosed) {
        emit(
          AccountDeletionState(
            status: AccountDeletionStatus.previewReady,
            preview: preview,
          ),
        );
      }
    } catch (error, stackTrace) {
      _emitFailure(error, stackTrace: stackTrace);
    }
  }

  Future<void> confirmDeletion() async {
    final AccountDeletionPreview? preview = state.preview;
    if (isClosed || state.isBusy || state.isSuccessful || preview == null) {
      return;
    }

    emit(
      AccountDeletionState(
        status: AccountDeletionStatus.confirming,
        preview: preview,
      ),
    );

    try {
      await _requestAccountDeletion.confirm();
      if (!isClosed) {
        emit(
          AccountDeletionState(
            status: AccountDeletionStatus.success,
            preview: preview,
          ),
        );
      }
    } catch (error, stackTrace) {
      _emitFailure(error, preview: preview, stackTrace: stackTrace);
    }
  }

  void _emitFailure(
    Object error, {
    AccountDeletionPreview? preview,
    required StackTrace stackTrace,
  }) {
    final AccountDeletionFailureKind kind = error is AccountDeletionFailure
        ? error.kind
        : AccountDeletionFailureKind.requestFailed;
    AppLogger.warning(
      'Account deletion workflow failed; no client data was deleted.',
      error: error,
      stackTrace: stackTrace,
    );
    if (!isClosed) {
      emit(
        AccountDeletionState(
          status: AccountDeletionStatus.failure,
          preview: preview,
          failure: kind,
        ),
      );
    }
  }
}
