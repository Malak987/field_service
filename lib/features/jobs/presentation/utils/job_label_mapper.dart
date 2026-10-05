import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';

/// Maps raw backend values (free `text` columns) to localized labels.
///
/// Both `jobs.status` and `jobs.job_type` are free text in the database, so
/// unknown values must never break the UI: anything without a dedicated
/// translation falls back to displaying the raw string.
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

  /// Localized label for a `jobs.job_type` value.
  String jobTypeLabel(String jobType) {
    return switch (jobType) {
      'renovation' => l10n.jobTypeRenovation,
      'kitchen_installation' => l10n.jobTypeKitchenInstallation,
      'maintenance' => l10n.jobTypeMaintenance,
      // Unknown backend value: show the raw string instead of failing.
      _ => jobType,
    };
  }
}
