import 'dart:async';

import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/features/authentication/domain/entities/account_deletion_failure.dart';
import 'package:field_service/features/authentication/presentation/pages/account_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';

void main() {
  late AppTestHarness app;

  setUp(() => app = AppTestHarness());
  tearDown(() => app.dispose());

  testWidgets('shows the dry-run before explicit deletion confirmation', (
    WidgetTester tester,
  ) async {
    final Completer<void> pendingPreview = Completer<void>();
    final Completer<void> pendingConfirmation = Completer<void>();
    app.authentication.pendingAccountDeletionPreview = pendingPreview;
    app.authentication.pendingAccountDeletionConfirm = pendingConfirmation;
    await app.configure(user: adminUser, initialLocation: AppRoutes.account);
    await app.pump(tester);

    expect(find.byType(AccountPage), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('account_delete_request_preview')),
    );
    await tester.tap(find.byKey(const Key('account_delete_request_preview')));
    await tester.pump();

    expect(app.authentication.accountDeletionPreviewCalls, 1);
    expect(app.authentication.accountDeletionConfirmCalls, 0);
    expect(app.authentication.clearLocalSessionCalls, 0);
    expect(find.text('Preparing deletion preview…'), findsOneWidget);

    pendingPreview.complete();
    await tester.pumpAndSettle();

    expect(find.text('Deletion preview'), findsOneWidget);
    expect(
      find.text('Your sign-in account and email address will be deleted.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Your employee record, work history, photos, and signatures will stay stored until the retention period ends.',
      ),
      findsOneWidget,
    );
    expect(app.authentication.accountDeletionConfirmCalls, 0);

    await tester.tap(
      find.byKey(const Key('account_delete_open_confirmation')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account_delete_confirmation_dialog')), findsOneWidget);
    expect(app.authentication.accountDeletionConfirmCalls, 0);

    await tester.tap(find.byKey(const Key('account_delete_confirm')));
    await tester.pump();

    expect(app.authentication.accountDeletionConfirmCalls, 1);
    expect(app.authentication.clearLocalSessionCalls, 0);
    expect(find.text('Deleting account…'), findsOneWidget);

    pendingConfirmation.complete();
    await tester.pumpAndSettle();

    expect(app.authentication.clearLocalSessionCalls, 1);
  });

  testWidgets('keeps the account page open for last active administrator', (
    WidgetTester tester,
  ) async {
    app.authentication.accountDeletionConfirmError = const AccountDeletionFailure(
      AccountDeletionFailureKind.lastActiveAdmin,
    );
    await app.configure(user: adminUser, initialLocation: AppRoutes.account);
    await app.pump(tester);

    await tester.ensureVisible(
      find.byKey(const Key('account_delete_request_preview')),
    );
    await tester.tap(find.byKey(const Key('account_delete_request_preview')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('account_delete_open_confirmation')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account_delete_confirm')));
    await tester.pumpAndSettle();

    expect(app.authentication.accountDeletionPreviewCalls, 1);
    expect(app.authentication.accountDeletionConfirmCalls, 1);
    expect(app.authentication.clearLocalSessionCalls, 0);
    expect(find.byType(AccountPage), findsOneWidget);
    expect(
      find.text(
        'You are the last active administrator. Add another active administrator before deleting this account.',
      ),
      findsWidgets,
    );
  });
}
