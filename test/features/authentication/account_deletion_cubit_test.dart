import 'dart:async';

import 'package:field_service/features/authentication/domain/entities/account_deletion_failure.dart';
import 'package:field_service/features/authentication/domain/entities/account_deletion_preview.dart';
import 'package:field_service/features/authentication/domain/usecases/request_account_deletion.dart';
import 'package:field_service/features/authentication/presentation/cubit/account_deletion_cubit.dart';
import 'package:field_service/features/authentication/presentation/cubit/account_deletion_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_authentication_repository.dart';

void main() {
  late TestAuthenticationRepository repository;
  late AccountDeletionCubit cubit;

  setUp(() {
    repository = TestAuthenticationRepository();
    cubit = AccountDeletionCubit(
      requestAccountDeletion: RequestAccountDeletion(repository),
    );
  });

  tearDown(() => cubit.close());

  test('requires a successful dry-run before confirmation can be sent', () async {
    await cubit.confirmDeletion();

    expect(repository.accountDeletionConfirmCalls, 0);
    expect(cubit.state.status, AccountDeletionStatus.initial);

    repository.accountDeletionPreview = const AccountDeletionPreview(
      serverMessage: 'Preview complete.',
    );
    await cubit.previewDeletion();

    expect(repository.accountDeletionPreviewCalls, 1);
    expect(cubit.state.status, AccountDeletionStatus.previewReady);
    expect(cubit.state.preview, repository.accountDeletionPreview);

    await cubit.confirmDeletion();

    expect(repository.accountDeletionConfirmCalls, 1);
    expect(cubit.state.status, AccountDeletionStatus.success);
    expect(repository.signOutCalls, 0);
    expect(repository.clearLocalSessionCalls, 0);
  });

  test('coalesces duplicate preview requests while the dry-run is pending', () async {
    final Completer<void> pendingPreview = Completer<void>();
    repository.pendingAccountDeletionPreview = pendingPreview;

    final Future<void> firstPreview = cubit.previewDeletion();
    await cubit.previewDeletion();

    expect(repository.accountDeletionPreviewCalls, 1);
    expect(cubit.state.status, AccountDeletionStatus.previewing);

    pendingPreview.complete();
    await firstPreview;
    expect(cubit.state.status, AccountDeletionStatus.previewReady);
  });

  test('surfaces the last-active-admin refusal without confirming deletion', () async {
    await cubit.previewDeletion();
    repository.accountDeletionConfirmError = const AccountDeletionFailure(
      AccountDeletionFailureKind.lastActiveAdmin,
    );

    await cubit.confirmDeletion();

    expect(repository.accountDeletionConfirmCalls, 1);
    expect(cubit.state.status, AccountDeletionStatus.failure);
    expect(
      cubit.state.failure,
      AccountDeletionFailureKind.lastActiveAdmin,
    );
    expect(cubit.state.preview, isNotNull);
    expect(repository.signOutCalls, 0);
    expect(repository.clearLocalSessionCalls, 0);
  });

  test('surfaces an invalid session without treating it as deletion success', () async {
    repository.accountDeletionPreviewError = const AccountDeletionFailure(
      AccountDeletionFailureKind.sessionInvalid,
    );

    await cubit.previewDeletion();

    expect(repository.accountDeletionPreviewCalls, 1);
    expect(cubit.state.status, AccountDeletionStatus.failure);
    expect(cubit.state.failure, AccountDeletionFailureKind.sessionInvalid);
    expect(repository.accountDeletionConfirmCalls, 0);
    expect(repository.signOutCalls, 0);
    expect(repository.clearLocalSessionCalls, 0);
  });
}
