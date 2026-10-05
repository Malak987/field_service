import 'package:field_service/app/app.dart';
import 'package:field_service/app/di/injection.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_test_harness.dart';
import 'support/test_authentication_repository.dart';

void main() {
  testWidgets('app rebuild preserves its one shared authentication cubit', (
    tester,
  ) async {
    final app = AppTestHarness();
    await app.configure(user: adminUser);
    addTearDown(app.dispose);
    await app.pump(tester);
    final cubit = sl<AuthenticationCubit>();
    expect(app.authentication.currentUserCalls, 1);

    await tester.pumpWidget(FieldServiceApp(router: app.router));
    await tester.pumpAndSettle();
    expect(sl<AuthenticationCubit>(), same(cubit));
    expect(app.authentication.currentUserCalls, 1);
    expect(cubit.isClosed, isFalse);
    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('View Jobs'), findsOneWidget);
  });
}
