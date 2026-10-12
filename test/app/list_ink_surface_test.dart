import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/features/admin/presentation/pages/admin_home_page.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/presentation/pages/jobs_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_test_harness.dart';
import '../support/test_authentication_repository.dart';

/// Guards the fix for "ListTile background color or ink splashes may be
/// invisible".
///
/// A [ListTile] (and any [InkWell]) paints its highlight on the nearest
/// [Material] ancestor. When the list surface was a decorated `Container`, the
/// nearest Material was the Scaffold's cream canvas underneath it, so the ink
/// was drawn behind the white panel and never appeared. The surfaces are now
/// `Material` widgets carrying the same colour, hairline border and radius.
///
/// The assertion is the colour of that nearest Material: the theme's surface
/// (white) means the ink lands on the panel the user can see; the scaffold
/// background (cream) means the old, invisible-ink arrangement.
void main() {
  late AppTestHarness app;
  setUp(() => app = AppTestHarness());
  tearDown(() => app.dispose());

  /// The colour of the nearest [Material] above the widget carrying [key].
  Color inkSurfaceOf(WidgetTester tester, Key key) {
    final Element element = tester.element(find.byKey(key));
    final Material? material = element
        .findAncestorWidgetOfExactType<Material>();
    expect(
      material,
      isNotNull,
      reason: '$key has no Material ancestor, so it can show no ink at all',
    );
    return material!.color ?? Colors.transparent;
  }

  Job _job({required String id, required int number}) => Job(
    id: id,
    jobNumber: number,
    customerId: 'cust-$id',
    customerName: 'Mina Customer',
    assignedEmployeeId: 'emp-1',
    assignedEmployeeName: 'Omar Technician',
    jobType: 'kitchen_renovation',
    description: 'Renovate the kitchen.',
    status: JobStatus(JobStatus.assigned),
    assignedAt: DateTime.utc(2026, 10, 1),
    startedAt: null,
    createdAt: DateTime.utc(2026, 10, 1),
    updatedAt: DateTime.utc(2026, 10, 1),
    expiresAt: DateTime.utc(2026, 12, 1),
  );

  testWidgets('the admin management rows sit on a real ink surface', (
    tester,
  ) async {
    await app.configure(user: adminUser);
    await app.pump(tester);

    final Color surface = Theme.of(
      tester.element(find.byType(AdminHomePage)),
    ).colorScheme.surface;
    // Sanity: the two must differ, otherwise this test proves nothing.
    expect(
      surface,
      isNot(Theme.of(tester.element(find.byType(AdminHomePage))).scaffoldBackgroundColor),
    );

    expect(
      inkSurfaceOf(tester, const Key('nav_admin_technicians')),
      surface,
      reason: 'the technicians row must paint its ink on the white panel',
    );
    expect(
      inkSurfaceOf(tester, const Key('nav_admin_customers')),
      surface,
      reason: 'the customers row must paint its ink on the white panel',
    );
  });

  testWidgets('the jobs list rows sit on a real ink surface', (tester) async {
    await app.configure(
      user: adminUser,
      initialLocation: AppRoutes.jobs,
      jobs: <Job>[_job(id: 'one', number: 1001)],
    );
    await app.pump(tester);

    final Color surface = Theme.of(
      tester.element(find.byType(JobsPage)),
    ).colorScheme.surface;

    expect(
      inkSurfaceOf(tester, const ValueKey<String>('job_card_one')),
      surface,
      reason: 'a job row must paint its ink on the white panel, not the canvas',
    );
  });
}
