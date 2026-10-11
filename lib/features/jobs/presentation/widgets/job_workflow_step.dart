import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// One numbered step of the job execution workflow.
///
/// The job runs in a fixed order — 1 start, 2 before photos, 3 work
/// description, 4 after photos, 5 signature, 6 review and complete — so every
/// section of the details page is presented inside this frame. The step
/// indicator is on top; the section itself supplies its own content below.
///
/// State is carried twice: the icon/number/text say it and the colour only
/// reinforces it, so the path still reads in monochrome.
class JobWorkflowStep extends StatelessWidget {
  const JobWorkflowStep({
    super.key,
    required this.step,
    required this.done,
    required this.current,
    required this.child,
  });

  /// 1-based position in the six-stage workflow.
  final int step;

  /// The stage is finished (its evidence exists, or the job is completed).
  final bool done;

  /// The stage the technician is expected to do next.
  final bool current;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(
          color: current ? AppColors.goldAccent : context.colors.outlineVariant,
          width: current ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _StepHeader(step: step, done: done, current: current),
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

/// Numbered step state: completed, current, or upcoming. Both the text and the
/// icon carry meaning; colour is a reinforcing accent, never the only cue.
class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.step,
    required this.done,
    required this.current,
  });

  final int step;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String stateLabel = done
        ? l10n.statusCompleted
        : current
        ? l10n.currentStepLabel
        : '';
    final String semanticLabel = stateLabel.isEmpty
        ? l10n.stepLabel(step)
        : '${l10n.stepLabel(step)}, $stateLabel';

    return Semantics(
      container: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? AppColors.primary
                    : current
                    ? AppColors.goldSurface
                    : context.colors.surface,
                border: Border.all(
                  color: done
                      ? AppColors.primary
                      : current
                      ? AppColors.goldAccent
                      : context.colors.outlineVariant,
                ),
              ),
              alignment: Alignment.center,
              child: done
                  ? const Icon(
                      Icons.check_rounded,
                      size: AppDimensions.iconSm,
                      color: AppColors.surface,
                    )
                  : Text(
                      '$step',
                      style: context.textStyles.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: current
                            ? AppColors.primaryDark
                            : context.colors.onSurfaceVariant,
                      ),
                    ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                l10n.stepLabel(step),
                style: context.textStyles.titleSmall,
              ),
            ),
            if (current)
              Container(
                constraints: const BoxConstraints(minHeight: 32),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.goldSurface,
                  borderRadius: AppRadius.circular,
                ),
                child: Text(
                  l10n.currentStepLabel,
                  style: context.textStyles.bodySmall?.copyWith(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
