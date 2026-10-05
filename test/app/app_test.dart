import 'package:field_service/app/app.dart';
import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_router.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/features/admin/presentation/pages/admin_home_page.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/domain/entities/auth_session_event.dart';
import 'package:field_service/features/authentication/domain/repositories/authentication_repository.dart';
import 'package:field_service/features/authentication/domain/usecases/get_current_user.dart';
import 'package:field_service/features/authentication/domain/usecases/sign_in.dart';
import 'package:field_service/features/authentication/domain/usecases/sign_out.dart';
import 'package:field_service/features/authentication/domain/usecases/watch_auth_state_changes.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/authentication/presentation/pages/auth_gate_page.dart';
import 'package:field_service/features/authentication/presentation/pages/login_page.dart';
import 'package:field_service/features/technician/presentation/pages/technician_home_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late _FakeAuthenticationRepository authenticationRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await configureDependencies();

    authenticationRepository = _FakeAuthenticationRepository();
    await sl.unregister<AuthenticationCubit>();
    sl.registerFactory<AuthenticationCubit>(
      () => AuthenticationCubit(
        signIn: SignIn(authenticationRepository),
        signOut: SignOut(authenticationRepository),
        getCurrentUser: GetCurrentUser(authenticationRepository),
        watchAuthStateChanges: WatchAuthStateChanges(authenticationRepository),
      ),
    );
  });

  tearDown(resetDependencies);

  group('application startup routing', () {
    test('resolves the router at the root location', () {
      final AppRouter appRouter = sl<AppRouter>();

      expect(
        appRouter.router.routeInformationProvider.value.uri.path,
        AppRoutes.root,
      );
    });

    testWidgets('routes a logged-out user at / through AuthGate to LoginPage', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester);

      expect(find.byType(AuthGatePage), findsOneWidget);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(
        find.text('Phase 3 — clean architecture foundation is in place.'),
        findsNothing,
      );
    });

    testWidgets('restores an admin session to AdminHomePage at /', (
      WidgetTester tester,
    ) async {
      authenticationRepository.currentUser = const AppUser(
        id: 'auth-admin-1',
        email: 'admin@example.com',
        role: 'admin',
      );

      await _pumpApp(tester);

      expect(find.byType(AdminHomePage), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
      expect(
        find.text('Phase 3 — clean architecture foundation is in place.'),
        findsNothing,
      );
    });

    testWidgets('restores a technician session to TechnicianHomePage at /', (
      WidgetTester tester,
    ) async {
      authenticationRepository.currentUser = const AppUser(
        id: 'auth-technician-1',
        email: 'technician@example.com',
        role: 'technician',
      );

      await _pumpApp(tester);

      expect(find.byType(TechnicianHomePage), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
      expect(
        find.text('Phase 3 — clean architecture foundation is in place.'),
        findsNothing,
      );
    });
  });
}

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(FieldServiceApp(router: sl<AppRouter>().router));
  await tester.pumpAndSettle();
}

class _FakeAuthenticationRepository implements AuthenticationRepository {
  AppUser? currentUser;

  @override
  Future<AppUser?> getCurrentUser() async => currentUser;

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<AppUser?> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

  @override
  Future<void> updatePassword({required String newPassword}) async {}

  @override
  Future<void> signOut() async {}

  @override
  Stream<AuthSessionEvent> watchAuthStateChanges() =>
      Stream<AuthSessionEvent>.empty();
}
