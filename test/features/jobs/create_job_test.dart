import 'dart:io';

import 'package:field_service/app/di/injection.dart';
import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/features/admin/presentation/pages/admin_home_page.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/domain/entities/auth_session_event.dart';
import 'package:field_service/features/authentication/presentation/pages/login_page.dart';
import 'package:field_service/features/customers/data/datasources/customers_local_data_source.dart';
import 'package:field_service/features/customers/data/models/customer_model.dart';
import 'package:field_service/features/customers/domain/entities/customer_sync_status.dart';
import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/customers/domain/usecases/get_customers.dart';
import 'package:field_service/features/customers/domain/usecases/refresh_customers.dart';
import 'package:field_service/features/employees/domain/usecases/get_active_technicians.dart';
import 'package:field_service/features/jobs/domain/usecases/create_job.dart';
import 'package:field_service/features/jobs/presentation/cubit/create_job_cubit.dart';
import 'package:field_service/features/employees/domain/entities/employee.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/pages/create_job_page.dart';
import 'package:field_service/features/jobs/presentation/pages/job_details_page.dart';
import 'package:field_service/features/jobs/presentation/pages/jobs_page.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_start_button.dart';
import 'package:field_service/features/technician/presentation/pages/technician_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';

/// Admin Create & Assign Job workflow tests (the corrected business model:
/// ADMIN creates → assigns → monitors; the technician executes).
///
/// The harness fake "server" mirrors the `create_job` RPC facts: only the
/// two supported categories, server-generated job number, `status =
/// 'assigned'` and a SERVER `assigned_at` (exposed as [serverStartedAt], the
/// fake's server clock) — the client never contributes a timestamp.

const Employee kMaxMueller = Employee(
  id: 'emp-max',
  name: 'Max Müller',
  role: 'technician',
);

const Employee kJohnTechnician = Employee(
  id: 'emp-john',
  name: 'John Technician',
  role: 'technician',
);

Job _job({
  required String id,
  required int number,
  String? assignedEmployeeId = 'emp-max',
  String status = JobStatus.assigned,
  DateTime? startedAt,
}) {
  return Job(
    id: id,
    jobNumber: number,
    customerId: 'cust-$id',
    assignedEmployeeId: assignedEmployeeId,
    jobType: JobCategory.kitchenRenovation,
    description: 'Customer wants the kitchen renovated.',
    status: JobStatus(status),
    startedAt: startedAt,
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
    expiresAt: DateTime.utc(2026, 12, 1),
  );
}

/// Cubit-level fakes for the fresh-device regression below: the point is
/// ONLY whether `loadOptions` nudges the EXISTING customer refresh — no
/// widget tree, connectivity or timers are involved.
class _SpyRefreshCustomers implements RefreshCustomers {
  int calls = 0;

  @override
  Future<void> call() async {
    calls++;
  }
}

class _CustomerStream implements GetCustomers {
  _CustomerStream(this.customers);

  final List<Customer> customers;

  @override
  Stream<List<Customer>> call() => Stream<List<Customer>>.value(customers);
}

class _StubTechnicians implements GetActiveTechnicians {
  @override
  Future<List<Employee>> call() async => const <Employee>[];
}

class _UnusedCreateJob implements CreateJob {
  @override
  Future<Job> call({
    required String customerId,
    required String jobType,
    String? description,
    required String assignedEmployeeId,
  }) {
    throw UnimplementedError('This test never submits a job.');
  }
}

void main() {
  late AppTestHarness app;

  setUp(() => app = AppTestHarness());
  tearDown(() => app.dispose());

  Future<void> tallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<void> signInAs(WidgetTester tester, AppUser user) async {
    app.authentication.currentUser = user;
    app.authentication.events.add(AuthSessionEvent.signedIn);
    await tester.pumpAndSettle();
  }

  Future<void> signOut(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Sign Out'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  }

  Future<void> seedCustomer(String name) async {
    await sl<CustomersLocalDataSource>().insert(
      CustomerModel(
        id: name,
        name: name,
        address: '10 Test Street',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        syncStatus: CustomerSyncStatus.synced,
      ),
    );
  }

  /// Dashboard → Jobs page.
  Future<void> openJobs(WidgetTester tester) async {
    await tester.tap(find.text('View Jobs'));
    await tester.pumpAndSettle();
    expect(find.byType(JobsPage), findsOneWidget);
  }

  /// Jobs page → Create Job form.
  Future<void> openCreateJob(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('create_job_fab')));
    await tester.pumpAndSettle();
    expect(find.byType(CreateJobPage), findsOneWidget);
  }

  Future<void> selectDropdownItem(
    WidgetTester tester,
    Key dropdownKey,
    String itemText,
  ) async {
    await tester.tap(find.byKey(dropdownKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(itemText).last);
    await tester.pumpAndSettle();
  }

  // ---------------------------------------------------------------------------
  // Create Job visibility per role
  // ---------------------------------------------------------------------------

  // Checklist 1+2: admin opens Jobs and sees Create Job.
  testWidgets('admin Jobs page offers Create Job', (tester) async {
    await app.configure(user: adminUser);
    await app.pump(tester);
    expect(find.byType(AdminHomePage), findsOneWidget);
    await openJobs(tester);

    expect(find.byKey(const Key('create_job_fab')), findsOneWidget);
    expect(find.text('Create Job'), findsOneWidget);
  });

  // Checklist 29 (partial): technicians never see Create Job — neither in the
  // UI nor via a typed URL / deep link.
  testWidgets('technician never sees or reaches Create Job', (tester) async {
    await app.configure(user: technicianUser);
    await app.pump(tester);
    expect(find.byType(TechnicianHomePage), findsOneWidget);
    await openJobs(tester);

    expect(find.byKey(const Key('create_job_fab')), findsNothing);
    expect(find.text('Create Job'), findsNothing);

    // Deep link attempt: the router guard bounces the technician home.
    app.router.go(AppRoutes.jobCreate);
    await tester.pumpAndSettle();
    expect(find.byType(CreateJobPage), findsNothing);
    expect(find.byType(TechnicianHomePage), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Fresh-device regression: the customer selector must not stay empty
  // ---------------------------------------------------------------------------

  // The customer dropdown streams the LOCAL mirror (offline-first rule). On
  // a device whose mirror is still empty — fresh install or cleared app
  // data — nothing filled it, because Create Job only LISTENED to the
  // mirror and never nudged the remote pull (only the Customers page did).
  // The fix: `loadOptions` triggers the EXISTING [RefreshCustomers]; the
  // pull merges backend rows into the mirror and the already-subscribed
  // stream delivers them to the dropdown. Offline the pull is a safe no-op
  // and the mirror stays the answer — that gate lives in the repository.
  test(
    'CreateJobCubit.loadOptions nudges the existing customer refresh',
    () async {
      final _SpyRefreshCustomers refresh = _SpyRefreshCustomers();
      final CreateJobCubit cubit = CreateJobCubit(
        getCustomers: _CustomerStream(const <Customer>[]),
        getActiveTechnicians: _StubTechnicians(),
        createJob: _UnusedCreateJob(),
        refreshCustomers: refresh,
      );

      await cubit.loadOptions();
      // The refresh is fired immediately (unawaited); let it land.
      await Future<void>.delayed(Duration.zero);

      expect(refresh.calls, 1);
      await cubit.close();
    },
  );

  test('customers arriving on the local stream reach the form state', () async {
    final Customer remote = Customer(
      id: 'remote-cust-1',
      name: 'Remote Customer',
      address: '1 Backend Street',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: CustomerSyncStatus.synced,
    );
    final CreateJobCubit cubit = CreateJobCubit(
      getCustomers: _CustomerStream(<Customer>[remote]),
      getActiveTechnicians: _StubTechnicians(),
      createJob: _UnusedCreateJob(),
      refreshCustomers: _SpyRefreshCustomers(),
    );

    await cubit.loadOptions();
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.customers, <Customer>[remote]);
    await cubit.close();
  });

  // ---------------------------------------------------------------------------
  // The admin Create & Assign flow
  // ---------------------------------------------------------------------------

  // Checklist 3–13: the full flow and the resulting authoritative facts.
  testWidgets('admin creates and assigns a job end to end', (tester) async {
    await tallSurface(tester);
    await app.configure(
      user: adminUser,
      withCustomers: true,
      technicians: const <Employee>[kMaxMueller, kJohnTechnician],
    );
    await seedCustomer('Thomas Schneider');
    await seedCustomer('Anna Müller');
    await app.pump(tester);
    await openJobs(tester);
    await openCreateJob(tester);

    // 3 — select the customer from the existing Customers feature.
    await selectDropdownItem(
      tester,
      const Key('create_job_customer_dropdown'),
      'Thomas Schneider',
    );

    // 4–6 — the category selector offers EXACTLY the two business values;
    // pick Kitchen Renovation. Legacy categories are gone for good.
    await tester.tap(find.byKey(const Key('create_job_category_dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('Home Renovation'), findsOneWidget);
    expect(find.text('Kitchen Renovation'), findsOneWidget);
    expect(find.text('Kitchen Installation'), findsNothing);
    expect(find.text('Renovation'), findsNothing);
    expect(find.text('Maintenance'), findsNothing);
    await tester.tap(find.text('Kitchen Renovation').last);
    await tester.pumpAndSettle();

    // 7 — the admin's initial description (the customer's request, NOT the
    // technician's future Work Details).
    await tester.enterText(
      find.byKey(const Key('create_job_description_field')),
      'Customer wants the entire kitchen renovated and cabinets replaced.',
    );

    // 8 — select an ACTIVE technician (only technicians are offered).
    await selectDropdownItem(
      tester,
      const Key('create_job_technician_dropdown'),
      'Max Müller',
    );

    // 9 — Create & Assign is one server action.
    await tester.tap(find.byKey(const Key('create_and_assign_job_button')));
    await tester.pumpAndSettle();

    // Success feedback, then back on the Jobs list.
    expect(find.text('Job created and assigned.'), findsOneWidget);
    expect(find.byType(CreateJobPage), findsNothing);
    expect(find.byType(JobsPage), findsOneWidget);

    // The fake server received exactly one request with the form facts.
    expect(app.createJobCalls, hasLength(1));
    expect(app.createJobCalls.single, <String, Object?>{
      'customer_id': 'Thomas Schneider',
      'job_type': 'kitchen_renovation',
      'description':
          'Customer wants the entire kitchen renovated and cabinets replaced.',
      'assigned_employee_id': 'emp-max',
    });

    // 10–13 — the created job's authoritative facts: status `assigned`,
    // correct customer, correct technician, correct category, and a SERVER
    // assignment timestamp (the client never invented one).
    final Job created = app.createdJobs.single;
    expect(created.status.value, JobStatus.assigned);
    expect(created.customerId, 'Thomas Schneider');
    expect(created.assignedEmployeeId, 'emp-max');
    expect(created.jobType, JobCategory.kitchenRenovation);
    expect(created.assignedAt, serverStartedAt);

    // The job immediately appears in the admin Jobs list.
    expect(find.text('#${created.jobNumber}'), findsOneWidget);
    expect(find.text('Kitchen Renovation'), findsOneWidget);
  });

  // Checklist 4+31 (UI level): the selector offers exactly the two supported
  // categories — nothing else, no free text.
  testWidgets('category selector offers exactly two categories', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(
      user: adminUser,
      withCustomers: true,
      technicians: const <Employee>[kMaxMueller],
    );
    await seedCustomer('Thomas Schneider');
    await app.pump(tester);
    await openJobs(tester);
    await openCreateJob(tester);

    await tester.tap(find.byKey(const Key('create_job_category_dropdown')));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownMenuItem<String>), findsNWidgets(2));
    expect(find.text('Home Renovation'), findsOneWidget);
    expect(find.text('Kitchen Renovation'), findsOneWidget);

    // Select Home Renovation and keep the choice visible in the form.
    await tester.tap(find.text('Home Renovation').last);
    await tester.pumpAndSettle();
    expect(find.text('Home Renovation'), findsOneWidget);

    // Leave the form via the back button (ends on the non-Drift Jobs
    // page so the customers stream closes inside the test body).
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(JobsPage), findsOneWidget);
  });

  // Validation: an incomplete form never reaches the server.
  testWidgets('incomplete form never reaches the server', (tester) async {
    await tallSurface(tester);
    await app.configure(
      user: adminUser,
      withCustomers: true,
      technicians: const <Employee>[kMaxMueller],
    );
    await seedCustomer('Thomas Schneider');
    await app.pump(tester);
    await openJobs(tester);
    await openCreateJob(tester);

    await tester.tap(find.byKey(const Key('create_and_assign_job_button')));
    await tester.pumpAndSettle();

    // Customer, category and technician are required.
    expect(find.text('This field is required.'), findsNWidgets(3));
    expect(app.createJobCalls, isEmpty);
    expect(find.byType(CreateJobPage), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  });

  // Server refusal (e.g. network, non-admin caller) keeps the admin on the
  // form with an error message — nothing half-created.
  testWidgets('server refusal keeps the admin on the form', (tester) async {
    await tallSurface(tester);
    await app.configure(
      user: adminUser,
      withCustomers: true,
      technicians: const <Employee>[kMaxMueller],
      createJobError: StateError('Only an active admin can create jobs.'),
    );
    await seedCustomer('Thomas Schneider');
    await app.pump(tester);
    await openJobs(tester);
    await openCreateJob(tester);

    await selectDropdownItem(
      tester,
      const Key('create_job_customer_dropdown'),
      'Thomas Schneider',
    );
    await selectDropdownItem(
      tester,
      const Key('create_job_category_dropdown'),
      'Kitchen Renovation',
    );
    await selectDropdownItem(
      tester,
      const Key('create_job_technician_dropdown'),
      'Max Müller',
    );

    await tester.tap(find.byKey(const Key('create_and_assign_job_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('The job could not be created. Please try again.'),
      findsOneWidget,
    );
    expect(find.byType(CreateJobPage), findsOneWidget);
    expect(app.createJobCalls, isEmpty);
    expect(app.createdJobs, isEmpty);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  });

  // ---------------------------------------------------------------------------
  // Admin vs Technician job details (checklist 14 + monitoring)
  // ---------------------------------------------------------------------------

  // Checklist 14: the admin's Job Details is monitoring-only — never a
  // Start Job button, never a photo capture action.
  testWidgets('admin job details are monitoring-only', (tester) async {
    await tallSurface(tester);
    final DateTime serverStart = DateTime.utc(2026, 10, 6, 9, 30);
    await app.configure(
      user: adminUser,
      jobs: <Job>[
        _job(id: 'job-1', number: 101),
        _job(
          id: 'job-2',
          number: 102,
          status: JobStatus.inProgress,
          startedAt: serverStart,
        ),
      ],
    );
    await app.pump(tester);
    await openJobs(tester);

    // Assigned job: monitoring fields, no Start Job.
    await tester.tap(find.text('#101'));
    await tester.pumpAndSettle();
    expect(find.byType(JobDetailsPage), findsOneWidget);
    expect(find.byType(JobStartButton), findsNothing);
    expect(find.byKey(const Key('start_job_button')), findsNothing);
    expect(find.text('Assigned'), findsWidgets);
    expect(app.startedJobIds, isEmpty); // nothing reached the backend

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // In-progress job: the started date is monitoring information, and the
    // Before Photos section is read-only (no Add action for admins). The
    // exact date string is locale/timezone-formatted by `formatJobDate`, so
    // assert the "Started:" line by prefix.
    await tester.tap(find.text('#102'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Started:'), findsOneWidget);
    expect(find.text('Before Photos'), findsOneWidget);
    expect(find.byKey(const Key('add_before_photo_button')), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(JobsPage), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // job_number is server-generated (regression for PostgreSQL error 428C9)
  // ---------------------------------------------------------------------------

  /// Fills the Create Job form with the given facts and submits it.
  Future<void> fillAndSubmit(
    WidgetTester tester, {
    String customer = 'Thomas Schneider',
    String category = 'Kitchen Renovation',
    String technician = 'Max Müller',
    String description = 'Customer request.',
  }) async {
    await selectDropdownItem(
      tester,
      const Key('create_job_customer_dropdown'),
      customer,
    );
    await selectDropdownItem(
      tester,
      const Key('create_job_category_dropdown'),
      category,
    );
    await tester.enterText(
      find.byKey(const Key('create_job_description_field')),
      description,
    );
    await selectDropdownItem(
      tester,
      const Key('create_job_technician_dropdown'),
      technician,
    );
    await tester.tap(find.byKey(const Key('create_and_assign_job_button')));
    await tester.pumpAndSettle();
  }

  // The fake "server" models the identity column: every Create & Assign gets
  // the next number — the client contributes none and receives it back.
  testWidgets('job numbers are generated server-side, never by the client', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(
      user: adminUser,
      withCustomers: true,
      technicians: const <Employee>[kMaxMueller],
    );
    await seedCustomer('Thomas Schneider');
    await app.pump(tester);
    await openJobs(tester);

    // First creation.
    await openCreateJob(tester);
    await fillAndSubmit(tester);
    expect(find.byType(JobsPage), findsOneWidget);

    // Second creation — the number must come from the server again.
    await openCreateJob(tester);
    await fillAndSubmit(tester, description: 'Second request.');
    expect(find.byType(JobsPage), findsOneWidget);

    expect(app.createdJobs, hasLength(2));
    final int first = app.createdJobs[0].jobNumber;
    final int second = app.createdJobs[1].jobNumber;
    expect(first, isPositive);
    expect(second, greaterThan(first));

    // Neither request carried a client-side job number.
    for (final Map<String, Object?> call in app.createJobCalls) {
      expect(call.containsKey('job_number'), isFalse);
    }
  });

  // ---------------------------------------------------------------------------
  // Technician names come from employees.name (no hardcoded placeholders)
  // ---------------------------------------------------------------------------

  // Checklist 5+fallback: the selector displays `employees.name` exactly as
  // stored; an unexpectedly nameless row falls back to its employee code —
  // never an invented placeholder like "Technician 1".
  testWidgets('technician selector shows real employee names', (tester) async {
    await tallSurface(tester);
    await app.configure(
      user: adminUser,
      withCustomers: true,
      technicians: const <Employee>[
        kMaxMueller, // name = 'Max Müller'
        Employee(
          id: 'emp-nameless',
          name: '', // unexpected data problem → code fallback
          employeeCode: 'TECH-007',
          role: 'technician',
        ),
      ],
    );
    await seedCustomer('Thomas Schneider');
    await app.pump(tester);
    await openJobs(tester);
    await openCreateJob(tester);

    await tester.tap(find.byKey(const Key('create_job_technician_dropdown')));
    await tester.pumpAndSettle();

    // The real stored name, verbatim.
    expect(find.text('Max Müller'), findsOneWidget);
    // The nameless row shows its code — not a fake human name.
    expect(find.text('TECH-007'), findsOneWidget);
    // No invented placeholders anywhere.
    expect(find.text('Technician 1'), findsNothing);
    expect(find.text('Technician 2'), findsNothing);

    // Pick the real-named technician; the form keeps the stored name.
    await tester.tap(find.text('Max Müller').last);
    await tester.pumpAndSettle();
    expect(find.text('Max Müller'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  });

  // Checklist 6: production UI code never hardcodes placeholder technician
  // names — the display value must always flow from `employees.name`.
  test('no hardcoded technician placeholder names in production code', () {
    final RegExp placeholder = RegExp(r'Technician\s+\d|Technician\s+\$\{');
    final List<String> offenders = <String>[];

    for (final FileSystemEntity entity in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final String content = entity.readAsStringSync();
      if (placeholder.hasMatch(content)) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'technician names must come from public.employees.name, '
          'never from hardcoded placeholders',
    );
  });

  // ---------------------------------------------------------------------------
  // Hand-off: the assigned technician receives and executes the job
  // ---------------------------------------------------------------------------

  // Checklist 9+12: after the admin's Create & Assign, the technician sees
  // the job in My Jobs, opens it and starts it — the full hand-off.
  testWidgets('assigned technician receives the created job and starts it', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(
      user: adminUser,
      withCustomers: true,
      technicians: const <Employee>[kMaxMueller],
    );
    await seedCustomer('Thomas Schneider');
    await app.pump(tester);
    await openJobs(tester);
    await openCreateJob(tester);
    await fillAndSubmit(tester);

    final Job created = app.createdJobs.single;
    expect(created.status.value, JobStatus.assigned);

    // Let the admin's success snackbar expire, so the technician's Start Job
    // snackbar is not queued behind it.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Hand the session over to the technician.
    await signOut(tester);
    await signInAs(tester, technicianUser);
    expect(find.byType(TechnicianHomePage), findsOneWidget);

    // The assigned job is in My Jobs — under its server-generated number.
    await tester.tap(find.text('View Jobs'));
    await tester.pumpAndSettle();
    expect(find.text('#${created.jobNumber}'), findsOneWidget);
    expect(find.text('Kitchen Renovation'), findsOneWidget);

    // The technician executes: Start Job works on the created job.
    await tester.tap(find.text('#${created.jobNumber}'));
    await tester.pumpAndSettle();
    expect(find.byType(JobDetailsPage), findsOneWidget);
    expect(find.byKey(const Key('start_job_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('start_job_button')));
    await tester.pumpAndSettle();

    expect(find.text('Job started'), findsOneWidget);
    expect(find.text('In Progress'), findsWidgets);
    expect(app.startedJobIds, <String>[created.id]);
  });

  // ---------------------------------------------------------------------------
  // Role switching (checklist 29/30)
  // ---------------------------------------------------------------------------

  testWidgets('role switch swaps the Create Job capability with the session', (
    tester,
  ) async {
    await app.configure(user: adminUser);
    await app.pump(tester);
    await openJobs(tester);
    expect(find.byKey(const Key('create_job_fab')), findsOneWidget);

    // Admin → technician: Create Job disappears, Customers stays gone.
    await signOut(tester);
    await signInAs(tester, technicianUser);
    expect(find.byType(TechnicianHomePage), findsOneWidget);
    expect(find.byKey(const Key('nav_customers')), findsNothing);
    await openJobs(tester);
    expect(find.byKey(const Key('create_job_fab')), findsNothing);

    // Technician → admin: Create Job and Customers come back.
    await signOut(tester);
    await signInAs(tester, adminUser);
    expect(find.byType(AdminHomePage), findsOneWidget);
    expect(find.byKey(const Key('nav_customers')), findsOneWidget);
    await openJobs(tester);
    expect(find.byKey(const Key('create_job_fab')), findsOneWidget);
  });
}
