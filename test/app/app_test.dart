import 'package:field_service/app/app.dart';
import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_router.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/app/router/pages/app_root_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(configureDependencies);
  tearDown(resetDependencies);

  group('application shell', () {
    test('resolves the router through the dependency graph', () {
      final AppRouter appRouter = sl<AppRouter>();

      expect(
        appRouter.router.routeInformationProvider.value.uri.path,
        AppRoutes.root,
      );
    });

    testWidgets('boots into the root route', (WidgetTester tester) async {
      await tester.pumpWidget(FieldServiceApp(router: sl<AppRouter>().router));
      await tester.pumpAndSettle();

      expect(find.byType(AppRootPage), findsOneWidget);
    });
  });
}
