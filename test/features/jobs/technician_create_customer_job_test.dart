import 'dart:async';

import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/features/authentication/presentation/pages/login_page.dart';
import 'package:field_service/features/jobs/domain/entities/accessible_customer.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/domain/entities/new_customer_draft.dart';
import 'package:field_service/features/jobs/domain/entities/technician_job_creation.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';
import 'package:field_service/features/jobs/domain/usecases/create_technician_customer_and_job.dart';
import 'package:field_service/features/jobs/domain/usecases/create_technician_job_for_customer.dart';
import 'package:field_service/features/jobs/domain/usecases/get_accessible_customers.dart';
import 'package:field_service/features/jobs/presentation/cubit/technician_job_form_cubit.dart';
import 'package:field_service/features/jobs/presentation/cubit/technician_job_form_state.dart';
import 'package:field_service/features/jobs/presentation/pages/job_details_page.dart';
import 'package:field_service/features/jobs/presentation/pages/technician_create_customer_job_page.dart';
import 'package:field_service/features/technician/presentation/pages/technician_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';

/// The technician's "Create Customer & Job" feature.
///
/// Cubit-level tests use fakes of the three use cases (no widget tree, no
/// connectivity); the widget tests run the REAL page through the REAL router
/// and DI graph with the harness' fake server.

const NewCustomerDraft kDraft = NewCustomerDraft(
  name: 'Anna Weber',
  address: 'Hauptstraße 12',
  phone: '+49 151 23456789',
  email: 'anna@example.com',
  city: 'Berlin',
  postalCode: '10115',
  notes: 'Ring twice.',
);

Job _createdJob({int number = 42}) => Job(
  id: 'job-created-$number',
  jobNumber: number,
  customerId: 'cust-created-$number',
  assignedEmployeeId: 'emp-me',
  jobType: JobCategory.kitchenRenovation,
  description: 'New kitchen fronts',
  status: const JobStatus(JobStatus.assigned),
  assignedAt: DateTime.utc(2026, 10, 11, 8),
  createdAt: DateTime.utc(2026, 10, 11, 8),
  updatedAt: DateTime.utc(2026, 10, 11, 8),
  expiresAt: DateTime.utc(2027, 1, 9),
);

// --- Use-case fakes -----------------------------------------------------------

class _RecordingCreateCustomerAndJob
    implements CreateTechnicianCustomerAndJob {
  _RecordingCreateCustomerAndJob({this.result, this.error});

  final TechnicianJobCreation? result;

  /// Mutable so a test can fail the first attempt and then retry the SAME
  /// form (the idempotency-key test).
  Object? error;

  /// Every accepted call, exactly as the cubit handed it over.
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];

  /// Releases an in-flight call (double-tap test).
  Completer<TechnicianJobCreation>? gate;

  @override
  Future<TechnicianJobCreation> call({
    required NewCustomerDraft customer,
    required String jobType,
    String? description,
    required String idempotencyKey,
  }) async {
    calls.add(<String, Object?>{
      'customer': customer,
      'jobType': jobType,
      'description': description,
      'idempotencyKey': idempotencyKey,
    });
    if (error != null) {
      throw error!; // ignore: only_throw_errors
    }
    final Completer<TechnicianJobCreation>? completer = gate;
    if (completer != null) {
      return completer.future;
    }
    return result ?? const TechnicianJobCreation.queued(jobId: 'queued-1');
  }
}

class _RecordingCreateJobForCustomer
    implements CreateTechnicianJobForCustomer {
  _RecordingCreateJobForCustomer({this.result, this.error});

  final TechnicianJobCreation? result;
  final Object? error;
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];

  @override
  Future<TechnicianJobCreation> call({
    required String customerId,
    required String jobType,
    String? description,
    required String idempotencyKey,
  }) async {
    calls.add(<String, Object?>{
      'customerId': customerId,
      'jobType': jobType,
      'description': description,
      'idempotencyKey': idempotencyKey,
    });
    if (error != null) {
      throw error!; // ignore: only_throw_errors
    }
    return result ?? const TechnicianJobCreation.queued(jobId: 'queued-1');
  }
}

class _StubAccessibleCustomers implements GetAccessibleCustomers {
  _StubAccessibleCustomers({
    this.customers = const <AccessibleCustomer>[],
    this.error,
  });

  final List<AccessibleCustomer> customers;
  final Object? error;
  final List<String> searches = <String>[];

  @override
  Future<List<AccessibleCustomer>> call({String search = ''}) async {
    searches.add(search);
    if (error != null) {
      throw error!; // ignore: only_throw_errors
    }
    return customers;
  }
}

TechnicianJobFormCubit _cubit({
  _RecordingCreateCustomerAndJob? create,
  _RecordingCreateJobForCustomer? createForCustomer,
  _StubAccessibleCustomers? accessible,
}) {
  return TechnicianJobFormCubit(
    createCustomerAndJob: create ?? _RecordingCreateCustomerAndJob(),
    createJobForCustomer: createForCustomer ?? _RecordingCreateJobForCustomer(),
    getAccessibleCustomers: accessible ?? _StubAccessibleCustomers(),
  );
}

void main() {
  group('TechnicianJobFormCubit — validation gate', () {
    test('an incomplete form is refused and never reaches the server', () async {
      final _RecordingCreateCustomerAndJob create =
          _RecordingCreateCustomerAndJob();
      final TechnicianJobFormCubit cubit = _cubit(create: create);

      // No category selected yet.
      final TechnicianJobFormOutcome outcome = await cubit
          .submitNewCustomerAndJob(customer: kDraft);

      expect(outcome, TechnicianJobFormOutcome.invalid);
      expect(create.calls, isEmpty);
      expect(cubit.state.showValidationErrors, isTrue);
      expect(cubit.state.isSubmitting, isFalse);

      await cubit.close();
    });

    test('the existing-customer mode requires a selected customer', () async {
      final _RecordingCreateJobForCustomer createForCustomer =
          _RecordingCreateJobForCustomer();
      final TechnicianJobFormCubit cubit = _cubit(
        createForCustomer: createForCustomer,
      );

      cubit.selectMode(TechnicianJobCustomerMode.existingCustomer);
      cubit.selectCategory(JobCategory.homeRenovation);
      await cubit.loadAccessibleCustomers();

      final TechnicianJobFormOutcome outcome = await cubit
          .submitJobForExistingCustomer();

      expect(outcome, TechnicianJobFormOutcome.invalid);
      expect(createForCustomer.calls, isEmpty);

      await cubit.close();
    });

    test('an unsupported category is never selectable', () async {
      final TechnicianJobFormCubit cubit = _cubit();

      cubit.selectCategory('painting');
      expect(cubit.state.selectedCategory, isNull);

      cubit.selectCategory(JobCategory.kitchenRenovation);
      expect(cubit.state.selectedCategory, JobCategory.kitchenRenovation);

      await cubit.close();
    });

    test('each mode only accepts its own submission', () async {
      final _RecordingCreateCustomerAndJob create =
          _RecordingCreateCustomerAndJob();
      final TechnicianJobFormCubit cubit = _cubit(create: create);
      cubit.selectCategory(JobCategory.homeRenovation);

      // Wrong mode: the existing-customer path refuses while in "new" mode.
      final TechnicianJobFormOutcome outcome = await cubit
          .submitJobForExistingCustomer();

      expect(outcome, TechnicianJobFormOutcome.invalid);
      expect(create.calls, isEmpty);

      await cubit.close();
    });
  });

  group('TechnicianJobFormCubit — submission outcomes', () {
    test('a server-confirmed creation exposes the authoritative job', () async {
      final Job job = _createdJob(number: 77);
      final _RecordingCreateCustomerAndJob create =
          _RecordingCreateCustomerAndJob(
            result: TechnicianJobCreation.created(job),
          );
      final TechnicianJobFormCubit cubit = _cubit(create: create);
      cubit.selectCategory(JobCategory.kitchenRenovation);

      final TechnicianJobFormOutcome outcome = await cubit
          .submitNewCustomerAndJob(
            customer: kDraft,
            description: 'New kitchen fronts',
          );

      expect(outcome, TechnicianJobFormOutcome.created);
      expect(cubit.state.createdJob, job);
      expect(cubit.state.queuedJobId, isNull);
      expect(cubit.state.isSubmitting, isFalse);
      expect(cubit.state.error, isNull);

      // The payload handed to the use case is exactly the form's content.
      expect(create.calls, hasLength(1));
      expect(create.calls.single['customer'], kDraft);
      expect(create.calls.single['jobType'], JobCategory.kitchenRenovation);
      expect(create.calls.single['description'], 'New kitchen fronts');

      await cubit.close();
    });

    test('an offline creation reports queued — never a server confirmation',
        () async {
      final TechnicianJobFormCubit cubit = _cubit(
        create: _RecordingCreateCustomerAndJob(
          result: const TechnicianJobCreation.queued(jobId: 'job-local-1'),
        ),
      );
      cubit.selectCategory(JobCategory.kitchenRenovation);

      final TechnicianJobFormOutcome outcome = await cubit
          .submitNewCustomerAndJob(customer: kDraft);

      expect(outcome, TechnicianJobFormOutcome.queuedForSync);
      expect(cubit.state.createdJob, isNull);
      expect(cubit.state.queuedJobId, 'job-local-1');

      await cubit.close();
    });

    test('a server refusal lands in the state and clears the spinner',
        () async {
      final TechnicianJobFormCubit cubit = _cubit(
        create: _RecordingCreateCustomerAndJob(
          error: const TechnicianJobCreationRejectedException(
            reason: TechnicianJobRejectReason.unauthorized,
          ),
        ),
      );
      cubit.selectCategory(JobCategory.kitchenRenovation);

      final TechnicianJobFormOutcome outcome = await cubit
          .submitNewCustomerAndJob(customer: kDraft);

      expect(outcome, TechnicianJobFormOutcome.failed);
      expect(cubit.state.error, isA<TechnicianJobCreationRejectedException>());
      expect(cubit.state.isSubmitting, isFalse);
      expect(cubit.state.createdJob, isNull);

      await cubit.close();
    });

    test('a second tap while a submission is in flight stays silent', () async {
      final _RecordingCreateCustomerAndJob create =
          _RecordingCreateCustomerAndJob();
      create.gate = Completer<TechnicianJobCreation>();
      final TechnicianJobFormCubit cubit = _cubit(create: create);
      cubit.selectCategory(JobCategory.kitchenRenovation);

      final Future<TechnicianJobFormOutcome> first = cubit
          .submitNewCustomerAndJob(customer: kDraft);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isSubmitting, isTrue);

      // Double tap.
      final TechnicianJobFormOutcome second = await cubit
          .submitNewCustomerAndJob(customer: kDraft);
      expect(second, TechnicianJobFormOutcome.inFlight);
      expect(create.calls, hasLength(1));

      create.gate!.complete(
        TechnicianJobCreation.created(_createdJob(number: 5)),
      );
      expect(await first, TechnicianJobFormOutcome.created);

      await cubit.close();
    });

    test(
      'the idempotency key is stable per form and unique across forms',
      () async {
        final _RecordingCreateCustomerAndJob create =
            _RecordingCreateCustomerAndJob();
        final TechnicianJobFormCubit cubit = _cubit(create: create);
        cubit.selectCategory(JobCategory.kitchenRenovation);

        // First attempt fails, the technician retries the SAME form.
        create.error = StateError('network');
        await cubit.submitNewCustomerAndJob(customer: kDraft);
        create.error = null;
        await cubit.submitNewCustomerAndJob(customer: kDraft);

        expect(create.calls, hasLength(2));
        expect(
          create.calls[0]['idempotencyKey'],
          create.calls[1]['idempotencyKey'],
          reason: 'a retry must reuse the form identity, or the server would '
              'create two jobs',
        );

        // A different form instance is a different creation.
        final TechnicianJobFormCubit other = _cubit();
        expect(other.idempotencyKey, isNot(cubit.idempotencyKey));

        await cubit.close();
        await other.close();
      },
    );
  });

  group('TechnicianJobFormCubit — accessible customers', () {
    test('loads the server-scoped list', () async {
      final _StubAccessibleCustomers accessible = _StubAccessibleCustomers(
        customers: const <AccessibleCustomer>[
          AccessibleCustomer(id: 'cust-1', name: 'Anna Weber'),
        ],
      );
      final TechnicianJobFormCubit cubit = _cubit(accessible: accessible);

      cubit.selectMode(TechnicianJobCustomerMode.existingCustomer);
      await cubit.loadAccessibleCustomers(search: 'anna');

      expect(accessible.searches, <String>['anna']);
      expect(cubit.state.accessibleCustomers, hasLength(1));
      expect(cubit.state.isLoadingCustomers, isFalse);
      expect(cubit.state.customersFailed, isFalse);

      await cubit.close();
    });

    test('a failed read is reported, not hidden', () async {
      final TechnicianJobFormCubit cubit = _cubit(
        accessible: _StubAccessibleCustomers(error: StateError('offline')),
      );

      await cubit.loadAccessibleCustomers();

      expect(cubit.state.customersFailed, isTrue);
      expect(cubit.state.isLoadingCustomers, isFalse);
      expect(cubit.state.accessibleCustomers, isEmpty);

      await cubit.close();
    });

    test('switching back to "new customer" clears the selection', () async {
      final TechnicianJobFormCubit cubit = _cubit(
        accessible: _StubAccessibleCustomers(
          customers: const <AccessibleCustomer>[
            AccessibleCustomer(id: 'cust-1', name: 'Anna Weber'),
          ],
        ),
      );

      cubit.selectMode(TechnicianJobCustomerMode.existingCustomer);
      await cubit.loadAccessibleCustomers();
      cubit.selectCustomer('cust-1');
      expect(cubit.state.selectedCustomerId, 'cust-1');

      cubit.selectMode(TechnicianJobCustomerMode.newCustomer);
      expect(cubit.state.selectedCustomerId, isNull);
      expect(cubit.state.isNewCustomerMode, isTrue);

      await cubit.close();
    });
  });

  // ---------------------------------------------------------------------------
  // UI + navigation (real page, real router, real DI, fake server)
  // ---------------------------------------------------------------------------

  group('technician UI', () {
    late AppTestHarness app;

    setUp(() => app = AppTestHarness());
    tearDown(() => app.dispose());

    /// The form is long; give the test surface enough height so every field
    /// is hit-testable without scrolling.
    Future<void> tallSurface(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }

    Future<void> openForm(WidgetTester tester) async {
      expect(
        find.byKey(const Key('nav_create_customer_job')),
        findsOneWidget,
        reason: 'the technician home must offer the entry point',
      );
      await tester.tap(find.byKey(const Key('nav_create_customer_job')));
      await tester.pumpAndSettle();
      expect(find.byType(TechnicianCreateCustomerJobPage), findsOneWidget);
    }

    testWidgets('the home screen offers the entry and the form opens', (
      WidgetTester tester,
    ) async {
      await tallSurface(tester);
      await app.configure(user: technicianUser);
      await app.pump(tester);
      expect(find.byType(TechnicianHomePage), findsOneWidget);

      await openForm(tester);

      // Both sections are on screen.
      expect(find.text('Customer'), findsWidgets);
      expect(find.text('Job details'), findsOneWidget);
      expect(
        find.byKey(const Key('technician_create_customer_job_button')),
        findsOneWidget,
      );
      // The assignee is the signed-in technician, read-only.
      expect(
        find.byKey(const Key('technician_job_assignee_field')),
        findsOneWidget,
      );
      expect(find.text(technicianUser.email), findsOneWidget);
    });

    testWidgets(
      'creating a customer and a job reports the real job number and opens '
      'the job',
      (WidgetTester tester) async {
        await tallSurface(tester);
        await app.configure(user: technicianUser, jobs: <Job>[]);
        await app.pump(tester);
        await openForm(tester);

        await tester.enterText(
          find.byKey(const Key('technician_customer_name_field')),
          'Anna Weber',
        );
        await tester.enterText(
          find.byKey(const Key('technician_customer_address_field')),
          'Hauptstraße 12',
        );
        await tester.enterText(
          find.byKey(const Key('technician_customer_phone_field')),
          '+49 151 23456789',
        );
        await tester.tap(
          find.byKey(const Key('technician_job_category_dropdown')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kitchen Renovation').last);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('technician_create_customer_job_button')),
        );
        await tester.pumpAndSettle();

        // The fake server created exactly one job for exactly one customer.
        expect(app.technicianCreatedJobs, hasLength(1));
        expect(app.technicianCreatedCustomers, hasLength(1));
        expect(app.technicianCreatedCustomers.single.name, 'Anna Weber');
        expect(app.technicianCreateCalls, hasLength(1));

        // The created job is assigned to the CALLER — the client never sent
        // an employee id, so the fake server resolved it from the session.
        final Job created = app.technicianCreatedJobs.single;
        expect(created.assignedEmployeeId, 'emp-tech');
        expect(created.status.value, JobStatus.assigned);
        // The payload carries no identity and no job number.
        expect(
          app.technicianCreateCalls.single.containsKey('assigned_employee_id'),
          isFalse,
        );
        expect(
          app.technicianCreateCalls.single.containsKey('job_number'),
          isFalse,
        );

        // Success message carries the REAL job number, then the job opens.
        expect(find.text('Job #${created.jobNumber} created.'), findsOneWidget);
        expect(find.byType(JobDetailsPage), findsOneWidget);
      },
    );

    testWidgets('an incomplete customer never reaches the server', (
      WidgetTester tester,
    ) async {
      await tallSurface(tester);
      await app.configure(user: technicianUser);
      await app.pump(tester);
      await openForm(tester);

      await tester.tap(
        find.byKey(const Key('technician_create_customer_job_button')),
      );
      await tester.pumpAndSettle();

      // The two required fields are flagged...
      expect(find.text('This field is required.'), findsWidgets);
      // ...and nothing was sent.
      expect(app.technicianCreatedJobs, isEmpty);
      expect(app.technicianCreatedCustomers, isEmpty);
      expect(find.byType(TechnicianCreateCustomerJobPage), findsOneWidget);
    });

    testWidgets('an invalid phone number is refused before submitting', (
      WidgetTester tester,
    ) async {
      await tallSurface(tester);
      await app.configure(user: technicianUser);
      await app.pump(tester);
      await openForm(tester);

      await tester.enterText(
        find.byKey(const Key('technician_customer_name_field')),
        'Anna Weber',
      );
      await tester.enterText(
        find.byKey(const Key('technician_customer_address_field')),
        'Hauptstraße 12',
      );
      await tester.enterText(
        find.byKey(const Key('technician_customer_phone_field')),
        'abc',
      );
      await tester.tap(
        find.byKey(const Key('technician_create_customer_job_button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid phone number.'), findsOneWidget);
      expect(app.technicianCreatedJobs, isEmpty);
    });

    testWidgets('an offline creation is reported as queued, not as saved', (
      WidgetTester tester,
    ) async {
      await tallSurface(tester);
      await app.configure(
        user: technicianUser,
        technicianCreateOffline: true,
      );
      await app.pump(tester);
      await openForm(tester);

      await tester.enterText(
        find.byKey(const Key('technician_customer_name_field')),
        'Anna Weber',
      );
      await tester.enterText(
        find.byKey(const Key('technician_customer_address_field')),
        'Hauptstraße 12',
      );
      await tester.tap(
        find.byKey(const Key('technician_job_category_dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home Renovation').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('technician_create_customer_job_button')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Saved on this device'), findsOneWidget);
      // No job number was invented and no job details were opened.
      expect(find.byType(JobDetailsPage), findsNothing);
      expect(find.textContaining('Job #'), findsNothing);
      expect(find.byType(TechnicianHomePage), findsOneWidget);
    });

    testWidgets('a server refusal keeps the technician on the form', (
      WidgetTester tester,
    ) async {
      await tallSurface(tester);
      await app.configure(
        user: technicianUser,
        technicianCreateError: const TechnicianJobCreationRejectedException(
          reason: TechnicianJobRejectReason.customerBlocked,
        ),
      );
      await app.pump(tester);
      await openForm(tester);

      await tester.enterText(
        find.byKey(const Key('technician_customer_name_field')),
        'Anna Weber',
      );
      await tester.enterText(
        find.byKey(const Key('technician_customer_address_field')),
        'Hauptstraße 12',
      );
      await tester.tap(
        find.byKey(const Key('technician_job_category_dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home Renovation').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('technician_create_customer_job_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This customer is blocked or deleted and cannot receive a new job.',
        ),
        findsOneWidget,
      );
      expect(find.byType(TechnicianCreateCustomerJobPage), findsOneWidget);
      expect(find.byType(JobDetailsPage), findsNothing);
    });

    testWidgets('an existing customer can be selected and used', (
      WidgetTester tester,
    ) async {
      await tallSurface(tester);
      await app.configure(
        user: technicianUser,
        accessibleCustomers: const <AccessibleCustomer>[
          AccessibleCustomer(
            id: 'cust-anna',
            name: 'Anna Weber',
            phone: '+49 151 23456789',
            address: 'Hauptstraße 12',
          ),
        ],
        technicianAllowedCustomerIds: <String>{'cust-anna'},
      );
      await app.pump(tester);
      await openForm(tester);

      await tester.tap(find.text('Existing customer'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('technician_existing_customer_tile')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('technician_customer_option_cust-anna')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('technician_job_category_dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kitchen Renovation').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('technician_create_customer_job_button')),
      );
      await tester.pumpAndSettle();

      expect(app.technicianCreatedJobs, hasLength(1));
      expect(app.technicianCreatedJobs.single.customerId, 'cust-anna');
      // No customer was registered — an existing one was used.
      expect(app.technicianCreatedCustomers, isEmpty);
    });

    testWidgets(
      'a customer the technician may not work for is refused by the server',
      (WidgetTester tester) async {
        await tallSurface(tester);
        await app.configure(
          user: technicianUser,
          accessibleCustomers: const <AccessibleCustomer>[
            AccessibleCustomer(id: 'cust-foreign', name: 'Foreign GmbH'),
          ],
          // `technicianAllowedCustomerIds` stays empty: the fake server
          // refuses the creation exactly like the RPC's 42501.
        );
        await app.pump(tester);
        await openForm(tester);

        await tester.tap(find.text('Existing customer'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('technician_existing_customer_tile')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('technician_customer_option_cust-foreign')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('technician_job_category_dropdown')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Home Renovation').last);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('technician_create_customer_job_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('You are not allowed to create this job.'),
          findsOneWidget,
        );
        expect(app.technicianCreatedJobs, isEmpty);
        expect(find.byType(TechnicianCreateCustomerJobPage), findsOneWidget);
      },
    );

    testWidgets('an admin cannot reach the technician form', (
      WidgetTester tester,
    ) async {
      await tallSurface(tester);
      await app.configure(user: adminUser);
      await app.pump(tester);

      app.router.go(AppRoutes.jobTechnicianCreate);
      await tester.pumpAndSettle();

      expect(find.byType(TechnicianCreateCustomerJobPage), findsNothing);
    });

    // -------------------------------------------------------------------------
    // The admin surface is untouched by this feature.
    // -------------------------------------------------------------------------

    testWidgets('the admin create-job route still refuses a technician', (
      WidgetTester tester,
    ) async {
      await tallSurface(tester);
      await app.configure(user: technicianUser);
      await app.pump(tester);

      app.router.go(AppRoutes.jobCreate);
      await tester.pumpAndSettle();

      expect(find.byType(TechnicianHomePage), findsOneWidget);
    });

    testWidgets('an unauthenticated visitor is bounced to the login', (
      WidgetTester tester,
    ) async {
      await tallSurface(tester);
      await app.configure();
      await app.pump(tester);
      expect(find.byType(LoginPage), findsOneWidget);

      app.router.go(AppRoutes.jobTechnicianCreate);
      await tester.pumpAndSettle();

      expect(find.byType(TechnicianCreateCustomerJobPage), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);
    });
  });
}
