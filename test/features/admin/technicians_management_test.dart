import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/features/admin/domain/entities/admin_account_status.dart';
import 'package:field_service/features/admin/domain/entities/managed_employee.dart';
import 'package:field_service/features/admin/presentation/pages/admin_technicians_page.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/technician/presentation/pages/technician_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';

/// Technician management (`إدارة الفنيين`) tests.
///
/// The harness fake mirrors the SERVER contract of
/// `supabase/admin_management_setup.sql`: only an active admin is admitted
/// (SQLSTATE 42501 otherwise), a soft deleted account can never change state
/// again, and the soft delete keeps the row with all of its counters — the
/// database already proves the stale-session/old-JWT behaviour, these tests
/// cover the app path that reaches it.

const ManagedEmployee kMaxMueller = ManagedEmployee(
  id: 'emp-max',
  name: 'Max Müller',
  role: 'technician',
  status: AdminAccountStatus.active,
  employeeCode: 'T-100',
  email: 'max@example.com',
  assignedJobs: 3,
  completedJobs: 2,
);

const ManagedEmployee kBlockedTechnician = ManagedEmployee(
  id: 'emp-blocked',
  name: 'Blocked Technician',
  role: 'technician',
  status: AdminAccountStatus.blocked,
  employeeCode: 'T-200',
  blockedAt: null,
  assignedJobs: 1,
  completedJobs: 0,
);

/// The signed-in admin owns this employee row: the database refuses a status
/// change on one's own account, and the UI must not even offer it.
const ManagedEmployee kOwnAdminRow = ManagedEmployee(
  id: 'emp-admin',
  name: 'Root Admin',
  role: 'admin',
  status: AdminAccountStatus.active,
);

const AppUser kAdminWithEmployeeId = AppUser(
  id: 'auth-admin-1',
  email: 'admin@example.com',
  role: 'admin',
  employeeId: 'emp-admin',
);

void main() {
  late AppTestHarness app;

  setUp(() => app = AppTestHarness());
  tearDown(() => app.dispose());

  Future<void> tallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<void> openTechnicians(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byKey(const Key('nav_admin_technicians')),
    );
    await tester.tap(find.byKey(const Key('nav_admin_technicians')));
    await tester.pumpAndSettle();
    expect(find.byType(AdminTechniciansPage), findsOneWidget);
  }

  Future<void> tapAndConfirm(WidgetTester tester, Key actionKey) async {
    await tester.ensureVisible(find.byKey(actionKey));
    await tester.tap(find.byKey(actionKey));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin_confirm_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin_confirm_accept')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'lists every technician with the real name, the state and the job history',
    (tester) async {
      await tallSurface(tester);
      await app.configure(
        user: adminUser,
        adminEmployees: const <ManagedEmployee>[
          kMaxMueller,
          kBlockedTechnician,
          kOwnAdminRow,
        ],
      );
      await app.pump(tester);
      await openTechnicians(tester);

      // Real names, never synthetic identities.
      expect(find.text('Max Müller'), findsOneWidget);
      expect(find.text('Blocked Technician'), findsOneWidget);

      // The state of every row is visible.
      expect(find.text('Active'), findsWidgets);
      expect(find.text('Blocked'), findsOneWidget);

      // Employee code + e-mail come from the backend row.
      expect(find.textContaining('T-100'), findsOneWidget);
      expect(find.textContaining('max@example.com'), findsOneWidget);

      // The job history counters are shown (never invented).
      expect(find.text('3 assigned · 2 completed'), findsOneWidget);

      // Administrator rows are listed but never manageable.
      expect(
        find.text('Administrator account — technician management does not apply to it.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('technician_block_emp-admin')), findsNothing);
    },
  );

  testWidgets(
    'blocking asks for confirmation, can be cancelled, and reaches the server',
    (tester) async {
      await tallSurface(tester);
      await app.configure(
        user: adminUser,
        adminEmployees: const <ManagedEmployee>[kMaxMueller],
      );
      await app.pump(tester);
      await openTechnicians(tester);

      // Cancelling the dialog performs NOTHING (safe default).
      await tester.tap(find.byKey(const Key('technician_block_emp-max')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin_confirm_dialog')), findsOneWidget);
      // The dialog explains that history is preserved.
      expect(find.textContaining('loses access immediately'), findsOneWidget);
      expect(
        find.textContaining('nothing is deleted'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('admin_confirm_cancel')));
      await tester.pumpAndSettle();
      expect(app.adminEmployeeStatusChanges, isEmpty);

      // Confirming sends exactly one transition and reports it.
      await tapAndConfirm(tester, const Key('technician_block_emp-max'));
      expect(app.adminEmployeeStatusChanges, <Map<String, Object?>>[
        <String, Object?>{'employee_id': 'emp-max', 'status': 'blocked'},
      ]);
      expect(app.adminEmployees.single.status, AdminAccountStatus.blocked);
      expect(find.text('Technician blocked.'), findsOneWidget);
      expect(find.text('Blocked'), findsOneWidget);
    },
  );

  testWidgets('unblocking returns a blocked technician to work', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(
      user: adminUser,
      adminEmployees: const <ManagedEmployee>[kBlockedTechnician],
    );
    await app.pump(tester);
    await openTechnicians(tester);

    // A blocked technician offers "Unblock", not a second "Block".
    expect(
      find.byKey(const Key('technician_unblock_emp-blocked')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('technician_block_emp-blocked')),
      findsNothing,
    );

    await tapAndConfirm(tester, const Key('technician_unblock_emp-blocked'));
    expect(app.adminEmployeeStatusChanges, <Map<String, Object?>>[
      <String, Object?>{'employee_id': 'emp-blocked', 'status': 'active'},
    ]);
    expect(app.adminEmployees.single.status, AdminAccountStatus.active);
    expect(find.text('Technician unblocked.'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets(
    'the soft delete keeps the employee row and its whole job history',
    (tester) async {
      await tallSurface(tester);
      await app.configure(
        user: adminUser,
        adminEmployees: const <ManagedEmployee>[kMaxMueller],
      );
      await app.pump(tester);
      await openTechnicians(tester);

      await tapAndConfirm(tester, const Key('technician_delete_emp-max'));

      // The row is still there — logically deleted, never hard deleted.
      final ManagedEmployee stored = app.adminEmployees.single;
      expect(stored.status, AdminAccountStatus.deleted);
      expect(stored.name, 'Max Müller');
      expect(stored.employeeCode, 'T-100');
      expect(stored.assignedJobs, 3);
      expect(stored.completedJobs, 2);
      expect(stored.deletedAt, isNotNull);

      expect(app.adminEmployeeStatusChanges, <Map<String, Object?>>[
        <String, Object?>{'employee_id': 'emp-max', 'status': 'deleted'},
      ]);
      expect(find.text('Technician deleted (history preserved).'), findsOneWidget);
      expect(find.text('Deleted'), findsOneWidget);
      // The row explains WHY nothing can be done any more (and that the
      // history survived) instead of showing the wrong "administrator" note.
      expect(
        find.text(
          'This technician is deleted. Jobs, photos and signatures stay '
          'recorded, and the account cannot be reactivated.',
        ),
        findsOneWidget,
      );
      // A deleted account can neither be re-blocked nor re-activated.
      expect(find.byKey(const Key('technician_block_emp-max')), findsNothing);
      expect(find.byKey(const Key('technician_unblock_emp-max')), findsNothing);
    },
  );

  testWidgets('a refused (non-admin) server answer is reported, never silent', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(user: adminUser, adminForbidden: true);
    await app.pump(tester);
    await openTechnicians(tester);

    // The database refuses the LIST for a non-admin caller: the screen says so
    // (and offers a retry) instead of showing an empty list.
    expect(find.text('Could not load'), findsOneWidget);
    expect(
      find.text(
        'Only an administrator may manage technicians and customers.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('admin_list_retry')), findsOneWidget);
  });

  testWidgets('a technician can never reach the management pages', (
    tester,
  ) async {
    await tallSurface(tester);
    await app.configure(user: technicianUser, adminEmployees: const <ManagedEmployee>[kMaxMueller]);
    await app.pump(tester);

    // Typed URL / deep link: the router guard sends the technician home before
    // the management page (or its data) is built.
    app.router.go(AppRoutes.adminTechnicians);
    await tester.pumpAndSettle();
    expect(find.byType(AdminTechniciansPage), findsNothing);
    expect(find.byType(TechnicianHomePage), findsOneWidget);

    app.router.go(AppRoutes.adminCustomers);
    await tester.pumpAndSettle();
    expect(find.byType(TechnicianHomePage), findsOneWidget);

    // The technician home has no management entry at all.
    expect(find.byKey(const Key('nav_admin_technicians')), findsNothing);
    expect(find.byKey(const Key('nav_admin_customers')), findsNothing);
  });

  testWidgets('the admin cannot manage their own account', (tester) async {
    await tallSurface(tester);
    await app.configure(
      user: kAdminWithEmployeeId,
      adminEmployees: const <ManagedEmployee>[kMaxMueller, kOwnAdminRow],
    );
    await app.pump(tester);
    await openTechnicians(tester);

    expect(
      find.text('This is your own account — you cannot change its status.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('technician_block_emp-admin')), findsNothing);
    expect(find.byKey(const Key('technician_delete_emp-admin')), findsNothing);
    // Other technicians stay manageable.
    expect(find.byKey(const Key('technician_block_emp-max')), findsOneWidget);
  });
}
