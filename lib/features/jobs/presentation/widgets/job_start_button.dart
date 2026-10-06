import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:flutter/material.dart';

/// The Start Job action for the Job Details page.
///
/// Renders only while the job is still `assigned` — once it is `in_progress`
/// (or anything else) the button disappears and the page shows the started
/// state instead. While a start request is being submitted the button shows
/// a spinner and is disabled, so double taps cannot enqueue twice.
///
/// Deliberately presentational: the outcome handling (snackbar, state flip)
/// stays with the page/cubit; this widget only reports the tap.
class JobStartButton extends StatelessWidget {
  const JobStartButton({
    super.key,
    required this.job,
    required this.isStarting,
    required this.onPressed,
  });

  /// The job this action belongs to.
  final Job job;

  /// A start request for this job is currently being submitted (queued or
  /// being pushed) — drives the busy/disabled state.
  final bool isStarting;

  /// Called when the user taps the button (never while [isStarting]).
  final VoidCallback onPressed;

  /// Whether the action applies to this job at all.
  bool get _isVisible => job.status.value == JobStatus.assigned;

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) {
      return const SizedBox.shrink();
    }

    final AppLocalizations l10n = context.l10n;

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: const Key('start_job_button'),
        onPressed: isStarting ? null : onPressed,
        icon: isStarting
            ? const SizedBox(
                width: AppDimensions.iconSm,
                height: AppDimensions.iconSm,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_arrow_rounded, size: AppDimensions.iconMd),
        label: Text(l10n.startJobButton),
      ),
    );
  }
}
