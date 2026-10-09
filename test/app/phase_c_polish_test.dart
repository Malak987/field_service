import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/locale_cubit.dart';
import 'package:field_service/features/admin/presentation/pages/admin_home_page.dart';
import 'package:field_service/features/authentication/presentation/pages/login_page.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_logo.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/pages/jobs_page.dart';
import 'package:field_service/features/technician/presentation/pages/technician_home_page.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_test_harness.dart';
import '../support/test_authentication_repository.dart';

/// Phase-C polish tests: localization-safe rendering (German labels must not
/// overflow), dark-mode rendering of the new surfaces, the job card's
/// status accent / next action, and the branded login screen.
///
/// Overflow bugs fail these tests automatically: a `RenderFlex overflowed`
/// during `pumpAndSettle` is reported as a test exception.

Job _job({
  required String id,
  required int number,
  String status = JobStatus.assigned,
}) {
  return Job(
    id: id,
    jobNumber: number,
    customerId: 'cust-$id',
    assignedEmployeeId: 'emp-tech-1',
    jobType: 'kitchen_renovation',
    description: 'Renovate the kitchen.',
    status: JobStatus(status),
    startedAt: null,
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
    expiresAt: DateTime.utc(2026, 12, 1),
  );
}

void main() {
  late AppTestHarness app;

  setUp(() => app = AppTestHarness());
  tearDown(() => app.dispose());

  // ---------------------------------------------------------------------------
  // German localization rendering (labels must fit, nothing may clip)
  // ---------------------------------------------------------------------------

  testWidgets('admin home renders fully in German without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await app.configure(user: adminUser);
    await app.pump(tester);

    // Locale persistence goes through a mocked platform channel — run it
    // outside the fake-async zone, then let the app rebuild. The app-scoped
    // cubit instance is reached THROUGH THE TREE (DI only has a factory).
    final BuildContext appContext = tester.element(find.byType(AdminHomePage));
    await tester.runAsync(
      () => appContext.read<LocaleCubit>().setLocale(const Locale('de')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AdminHomePage), findsOneWidget);
    // The long German nav labels fit in the bottom bar.
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Küche'), findsOneWidget);
    expect(find.text('Haussanierung'), findsOneWidget);
    expect(find.text('Konto'), findsOneWidget);
    // German dashboard sections.
    expect(find.text('SCHNELLZUGRIFF'), findsOneWidget);
    expect(find.text('ÜBERSICHT'), findsOneWidget);
    expect(find.text('KATEGORIEN'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(390, 800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('technician jobs list renders in German without overflow', (
    tester,
  ) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[_job(id: 'job-1', number: 101)],
    );
    await app.pump(tester);

    // Same as above: switch through the app-scoped cubit instance.
    final BuildContext appContext = tester.element(
      find.byType(TechnicianHomePage),
    );
    await tester.runAsync(
      () => appContext.read<LocaleCubit>().setLocale(const Locale('de')),
    );
    await tester.pumpAndSettle();

    // Technician reaches My Jobs and the German next-action caption fits.
    await tester.tap(find.byKey(const Key('bottom_nav_my_jobs')));
    await tester.pumpAndSettle();
    expect(find.byType(JobsPage), findsOneWidget);
    expect(find.text('Als Nächstes: Auftrag starten'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // One fixed brand theme — platform brightness never changes the app
  // ---------------------------------------------------------------------------

  testWidgets('admin home renders the fixed brand theme regardless of '
      'platform brightness', (tester) async {
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );

    await app.configure(
      user: adminUser,
      jobs: <Job>[_job(id: 'job-1', number: 101)],
    );
    // The app builds AFTER the brightness override. There is no dark theme:
    // the fixed brand theme must render identically.
    await app.pump(tester);

    expect(find.byType(AdminHomePage), findsOneWidget);
    expect(find.byKey(const Key('bottom_nav_home')), findsOneWidget);
    expect(find.text('View Jobs'), findsOneWidget);

    final BuildContext context = tester.element(find.byType(AdminHomePage));
    expect(context.theme.brightness, Brightness.light);
    expect(context.theme.scaffoldBackgroundColor, const Color(0xFFF6F1E7));
  });

  // ---------------------------------------------------------------------------
  // Job card: status-driven next action (technicians) and admin restraint
  // ---------------------------------------------------------------------------

  testWidgets('technician job cards show the status-derived next action', (
    tester,
  ) async {
    await app.configure(
      user: technicianUser,
      jobs: <Job>[
        _job(id: 'job-1', number: 101),
        _job(id: 'job-2', number: 102, status: JobStatus.inProgress),
      ],
    );
    await app.pump(tester);

    await tester.tap(find.byKey(const Key('bottom_nav_my_jobs')));
    await tester.pumpAndSettle();

    expect(find.text('Next: Start Job'), findsOneWidget);
    expect(find.text('Next: Continue Job'), findsOneWidget);
    expect(find.byType(JobsListItem), findsNWidgets(2));
  });

  testWidgets('admin job cards never show the next-action caption', (
    tester,
  ) async {
    await app.configure(
      user: adminUser,
      jobs: <Job>[
        _job(id: 'job-1', number: 101),
        _job(id: 'job-2', number: 102, status: JobStatus.inProgress),
      ],
    );
    await app.pump(tester);

    await tester.tap(find.byKey(const Key('nav_jobs')));
    await tester.pumpAndSettle();

    expect(find.byType(JobsPage), findsOneWidget);
    expect(find.textContaining('Next: '), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // Branded login screen
  // ---------------------------------------------------------------------------

  testWidgets('login screen renders the brand mark in both modes', (
    tester,
  ) async {
    await app.configure(user: null);
    await app.pump(tester);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(AuthLogo), findsOneWidget);

    // Dark-mode rebuild of the same screen.
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    await app.pump(tester);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(AuthLogo), findsOneWidget);
  });
}
