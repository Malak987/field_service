import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/localization/locale_cubit.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/pages/job_details_page.dart';
import 'package:field_service/features/jobs/presentation/pages/jobs_page.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_list_card.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_loading_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_test_harness.dart';
import '../support/test_authentication_repository.dart';

Job _job({
  required String id,
  required int number,
  String name = 'Mina Customer',
  String status = JobStatus.assigned,
  String category = 'kitchen_renovation',
  String? technician = 'Omar Technician',
  String? description = 'Repair the sink and replace the counter.',
}) => Job(
  id: id,
  jobNumber: number,
  customerId: 'customer-$id',
  customerName: name,
  assignedEmployeeId: 'employee-1',
  assignedEmployeeName: technician,
  jobType: category,
  description: description,
  status: JobStatus(status),
  assignedAt: DateTime.utc(2026, 10, 1),
  startedAt: null,
  createdAt: DateTime.utc(2026, 10, 1),
  updatedAt: DateTime.utc(2026, 10, 1),
  expiresAt: DateTime.utc(2026, 12, 1),
);

void main() {
  late AppTestHarness app;
  setUp(() => app = AppTestHarness());
  tearDown(() => app.dispose());

  testWidgets('admin sees real job fields, assigned technician and create action', (tester) async {
    await app.configure(
      user: adminUser,
      initialLocation: AppRoutes.jobs,
      jobs: <Job>[
        _job(id: 'one', number: 1001),
        _job(id: 'two', number: 1002, name: 'Lena Home', status: JobStatus.completed, category: 'home_renovation'),
      ],
    );
    await app.pump(tester);

    expect(find.byType(JobsPage), findsOneWidget);
    expect(find.byType(JobsListCard), findsNWidgets(2));
    expect(find.text('#1001'), findsOneWidget);
    expect(find.text('Mina Customer'), findsOneWidget);
    expect(find.text('Omar Technician'), findsOneWidget);
    expect(find.byKey(const Key('create_job_fab')), findsOneWidget);
    expect(find.text('Assigned · 1'), findsOneWidget);
    expect(find.text('Completed · 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('job_card_one')));
    await tester.pumpAndSettle();
    expect(find.byType(JobDetailsPage), findsOneWidget);
  });

  testWidgets('technician sees assigned-work presentation without admin actions', (tester) async {
    await app.configure(
      user: technicianUser,
      initialLocation: AppRoutes.jobs,
      jobs: <Job>[_job(id: 'tech-job', number: 2001)],
    );
    await app.pump(tester);

    expect(find.byType(JobsListCard), findsOneWidget);
    expect(find.text('Omar Technician'), findsNothing);
    expect(find.byKey(const Key('create_job_fab')), findsNothing);
    expect(find.text('Next: Start Job'), findsOneWidget);
  });

  testWidgets('local search, clear search, category and status filters compose', (tester) async {
    await app.configure(
      user: adminUser,
      initialLocation: AppRoutes.jobs,
      jobs: <Job>[
        _job(id: 'one', number: 1001, name: 'Mina Kitchen'),
        _job(id: 'two', number: 1002, name: 'Lena House', status: JobStatus.completed, category: 'home_renovation'),
      ],
    );
    await app.pump(tester);

    await tester.enterText(find.byKey(const Key('jobs_search_field')), 'Lena');
    await tester.pumpAndSettle();
    expect(find.byType(JobsListCard), findsOneWidget);
    expect(find.text('#1002'), findsOneWidget);
    expect(find.byKey(const Key('jobs_clear_search')), findsOneWidget);

    // Category filter composes with the active query instead of replacing it.
    await tester.tap(find.byType(ChoiceChip).at(2));
    await tester.pumpAndSettle();
    expect(find.byType(JobsListCard), findsOneWidget);
    expect(find.text('#1002'), findsOneWidget);

    await tester.tap(find.byKey(const Key('jobs_clear_search')));
    await tester.pumpAndSettle();
    expect(find.byType(JobsListCard), findsOneWidget);
    expect(find.text('#1002'), findsOneWidget);

    await tester.tap(find.byType(ChoiceChip).at(1));
    await tester.pumpAndSettle();
    expect(find.text('No matching jobs'), findsOneWidget);

    await tester.tap(find.byKey(const Key('jobs_clear_filters')));
    await tester.pumpAndSettle();
    expect(find.byType(JobsListCard), findsNWidgets(2));
  });

  testWidgets('status filter narrows results and clear filters restores them', (tester) async {
    await app.configure(
      user: adminUser,
      initialLocation: AppRoutes.jobs,
      jobs: <Job>[
        _job(id: 'assigned', number: 1),
        _job(id: 'complete', number: 2, status: JobStatus.completed),
      ],
    );
    await app.pump(tester);

    await tester.tap(find.byKey(const Key('jobs_status_filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed').last);
    await tester.pumpAndSettle();
    expect(find.byType(JobsListCard), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('#1'), findsNothing);

    await tester.tap(find.byKey(const Key('jobs_clear_filters')));
    await tester.pumpAndSettle();
    expect(find.byType(JobsListCard), findsNWidgets(2));
  });

  testWidgets('empty state is shown when no jobs are returned', (tester) async {
    await app.configure(user: adminUser, initialLocation: AppRoutes.jobs);
    await app.pump(tester);
    expect(find.text('No jobs yet'), findsOneWidget);

  });

  testWidgets('filtered no-results state offers a reset', (tester) async {
    await app.configure(
      user: adminUser,
      initialLocation: AppRoutes.jobs,
      jobs: <Job>[_job(id: 'one', number: 1)],
    );
    await app.pump(tester);
    await tester.enterText(find.byKey(const Key('jobs_search_field')), 'does-not-exist');
    await tester.pumpAndSettle();
    expect(find.text('No matching jobs'), findsOneWidget);
    expect(find.byKey(const Key('jobs_clear_filters')), findsOneWidget);
  });

  testWidgets('loading state is localized and announced', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: JobsLoadingView()),
      ),
    );
    await tester.pump();
    expect(find.text('Loading jobs'), findsOneWidget);
    expect(find.bySemanticsLabel('Loading jobs'), findsOneWidget);
  });

  testWidgets('error state exposes retry', (tester) async {
    await app.configure(user: adminUser, initialLocation: AppRoutes.jobs, jobsOffline: true);
    await app.pump(tester);
    expect(find.text('Something went wrong'), findsOneWidget);
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong'), findsOneWidget);
  });

  testWidgets('German list controls and cards fit 360px and 390px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await app.configure(
      user: adminUser,
      initialLocation: AppRoutes.jobs,
      jobs: <Job>[
        _job(id: 'long', number: 900001, name: 'Lange Kundin mit sehr langem Namen Musterfrau', technician: 'Ein Techniker mit sehr langem Namen'),
      ],
    );
    await app.pump(tester);
    final BuildContext context = tester.element(find.byType(JobsPage));
    await tester.runAsync(() => context.read<LocaleCubit>().setLocale(const Locale('de')));
    await tester.pumpAndSettle();
    expect(find.text('Kategorie'), findsOneWidget);
    expect(find.text('Status'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(390, 850));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
