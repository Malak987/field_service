import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';

/// Maps raw backend values (free `text` columns) to localized labels.
///
/// `jobs.status` is free text in the database and `jobs.job_type` is
/// constrained to the two business categories — but either way unknown values
/// must never break the UI: anything without a dedicated translation falls
/// back to displaying the raw string.
class JobLabelMapper {
  const JobLabelMapper(this.l10n);

  final AppLocalizations l10n;

  /// Localized label for a [JobStatus].
  String statusLabel(JobStatus status) {
    return switch (status.value) {
      JobStatus.assigned => l10n.statusAssigned,
      JobStatus.started => l10n.statusStarted,
      JobStatus.inProgress => l10n.statusInProgress,
      JobStatus.completed => l10n.statusCompleted,
      JobStatus.cancelled => l10n.statusCancelled,
      // Unknown backend value: show the raw string instead of failing.
      _ => status.value,
    };
  }

  /// Localized label for a `jobs.job_type` value (the job category).
  ///
  /// The business supports exactly two categories ([JobCategory]); legacy
  /// values were migrated on the server and never appear here — a row that
  /// somehow still carries one displays its raw value rather than a fake
  /// category label.
  String jobTypeLabel(String jobType) {
    return switch (jobType) {
      JobCategory.homeRenovation => l10n.jobCategoryHomeRenovation,
      JobCategory.kitchenRenovation => l10n.jobCategoryKitchenRenovation,
      // Unknown backend value: show the raw string instead of failing.
      _ => jobType,
    };
  }
}
