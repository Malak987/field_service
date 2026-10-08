import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The "Complete Job" section of the Job Details page — the FINAL workflow
/// step, shown to the assigned technician while the job is `in_progress`.
///
/// Purely presentational, same contract pattern as the other sections:
/// * lists the four completion requirements (before photos, work
///   description, after photos, customer signature) with a check mark for
///   each one the CLIENT currently knows to exist — helpful UX, never the
///   authority: the `complete_job` RPC re-validates every condition
///   server-side and may still refuse (e.g. a capture that has not been
///   synced yet),
/// * the **Complete Job** button is disabled while any requirement is
///   known-missing or a request is in flight, and shows a busy spinner
///   while the server decides,
/// * all logic lives in the cubit/repository — this widget only reports
///   taps and renders state.
class CompleteJobSection extends StatelessWidget {
  const CompleteJobSection({
    super.key,
    required this.hasBeforePhoto,
    required this.hasWorkDescription,
    required this.hasAfterPhoto,
    required this.hasSignature,
    required this.hasPendingUploads,
    required this.hasFailedUploads,
    required this.isCompleting,
    required this.onComplete,
    required this.onRetry,
  });

  /// The client knows of at least one before photo for this job.
  final bool hasBeforePhoto;

  /// The client knows of a non-blank work description for this job.
  final bool hasWorkDescription;

  /// The client knows of at least one after photo for this job.
  final bool hasAfterPhoto;

  /// The client knows of a captured customer signature for this job.
  final bool hasSignature;

  /// At least one required file (before/after photo, signature) exists
  /// locally but its upload has not been confirmed yet (`sync_status` still
  /// `pending` — covers queued AND in-flight operations). The server cannot
  /// see such files, so completion must wait.
  final bool hasPendingUploads;

  /// At least one required file's upload sits in the queue's `failed`
  /// state (existing failed-ids plumbing). Completion stays disabled and
  /// the section points at the shared Retry mechanism.
  final bool hasFailedUploads;

  /// A completion request is currently being submitted to the server —
  /// disables the button and shows the busy state (double-tap safety).
  final bool isCompleting;

  /// Called when the technician taps **Complete Job**.
  final VoidCallback onComplete;

  /// Retries the failed uploads — the SAME shared retry mechanism the
  /// photo/signature sections use (`retryFailedSyncs`).
  final VoidCallback onRetry;

  /// Every requirement the client knows about is present. The server may
  /// still refuse — this flag only drives the button's enabled state.
  bool get _allMet =>
      hasBeforePhoto && hasWorkDescription && hasAfterPhoto && hasSignature;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l10n.completeJobButton, style: context.textStyles.titleMedium),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.completionRequirementsTitle,
          style: context.textStyles.bodyMedium?.copyWith(
            color: AppColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _RequirementLine(
          key: const Key('completion_requirement_before_photos'),
          label: l10n.beforePhotosTitle,
          met: hasBeforePhoto,
        ),
        _RequirementLine(
          key: const Key('completion_requirement_work_description'),
          label: l10n.workDescriptionTitle,
          met: hasWorkDescription,
        ),
        _RequirementLine(
          key: const Key('completion_requirement_after_photos'),
          label: l10n.afterPhotosTitle,
          met: hasAfterPhoto,
        ),
        _RequirementLine(
          key: const Key('completion_requirement_customer_signature'),
          label: l10n.customerSignatureTitle,
          met: hasSignature,
        ),
        // Sync readiness (server truth requires registered files): a local
        // file alone is NOT sufficient — while a required upload is pending
        // or failed the technician sees exactly that instead of guessing.
        if (hasFailedUploads) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              const Icon(
                Icons.cloud_off_rounded,
                size: AppDimensions.iconMd,
                color: AppColors.error,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.uploadFailedLabel,
                  style: context.textStyles.bodyMedium?.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
              TextButton(
                key: const Key('retry_required_files_button'),
                onPressed: onRetry,
                child: Text(l10n.retryButton),
              ),
            ],
          ),
        ] else if (hasPendingUploads) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              const Icon(
                // Static on purpose: an indeterminate spinner here would
                // animate forever while uploads are pending.
                Icons.cloud_upload_rounded,
                size: AppDimensions.iconMd,
                color: AppColors.textSecondaryLight,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.waitingForFileSync,
                  style: context.textStyles.bodyMedium?.copyWith(
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          key: const Key('complete_job_button'),
          // Existence is necessary but not sufficient: every required file
          // must also have reached the `synced` state (server-registered)
          // before the authoritative RPC is offered.
          onPressed:
              _allMet &&
                  !hasPendingUploads &&
                  !hasFailedUploads &&
                  !isCompleting
              ? onComplete
              : null,
          icon: isCompleting
              ? const SizedBox(
                  width: AppDimensions.iconSm,
                  height: AppDimensions.iconSm,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(
                  Icons.check_circle_outline_rounded,
                  size: AppDimensions.iconMd,
                ),
          label: Text(
            isCompleting ? l10n.uploadingLabel : l10n.completeJobButton,
          ),
        ),
      ],
    );
  }
}

/// One line of the completion checklist: ✓ requirement met, ○ still open.
class _RequirementLine extends StatelessWidget {
  const _RequirementLine({super.key, required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          Icon(
            met
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: AppDimensions.iconMd,
            color: met ? AppColors.success : AppColors.textSecondaryLight,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: context.textStyles.bodyMedium?.copyWith(
                color: met ? null : AppColors.textSecondaryLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
