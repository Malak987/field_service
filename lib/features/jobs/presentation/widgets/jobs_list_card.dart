import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/presentation/widgets/jobs_list_item.dart';
import 'package:flutter/material.dart';

/// One row of the jobs list.
///
/// This is the list's row slot, not a second card design: the row itself is
/// [JobsListItem], the app's single job row, and every pixel the user sees
/// comes from there. The jobs list addresses its rows through this widget
/// (`job_card_<id>` keys, the list surface's hairline rhythm), exactly as the
/// dashboards address theirs through [JobsListItem] — one design, two names for
/// two different roles: "a row of this list" and "a job row".
///
/// Keeping the design in one place is what stops the list and the dashboards
/// from drifting apart: the same job looked different in the two places before.
class JobsListCard extends StatelessWidget {
  const JobsListCard({
    super.key,
    required this.job,
    required this.isAdmin,
    required this.onTap,
  });

  final Job job;

  /// Admins also see who the job is assigned to; technicians see the next
  /// action instead.
  final bool isAdmin;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => JobsListItem(
    job: job,
    showAssignedTechnician: isAdmin,
    showNextAction: !isAdmin,
    // This list's category filter chips spell out both categories right above
    // the rows, so the rows do not repeat them (see [JobsListItem]).
    showCategory: false,
    onTap: onTap,
  );
}
