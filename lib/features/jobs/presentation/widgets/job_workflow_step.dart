import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// One numbered stage of the existing six-stage job workflow.
///
/// The component does not decide what a technician can do; callers provide the
/// existing [done] and [current] facts. It turns those facts into a scan-friendly
/// execution frame with a restrained state rail and a clearly separated body.
class JobWorkflowStep extends StatelessWidget {
  const JobWorkflowStep({
    super.key,
    required this.step,
    required this.done,
    required this.current,
    required this.child,
  });

  final int step;
  final bool done;
  final bool current;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Color accent = done
        ? AppColors.success
        : current
        ? AppColors.goldDeep
        : context.colors.outlineVariant;

    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(
          color: current ? AppColors.goldAccent : context.colors.outlineVariant,
          width: current ? AppDimensions.focusedBorderWidth : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 4, color: accent),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _StepHeader(step: step, done: done, current: current),
                const SizedBox(height: AppSpacing.md),
                Divider(height: 1, color: context.colors.outlineVariant),
                const SizedBox(height: AppSpacing.md),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? AppColors.success
                    : current
                    ? AppColors.goldSurface
                    : AppColors.surfaceMuted,
                border: Border.all(
                  color: done
                      ? AppColors.success
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
                      color: AppColors.onBrand,
                    )
                  : Text(
                      '$step',
                      style: context.textStyles.labelMedium?.copyWith(
                        color: current
                            ? AppColors.goldDeep
                            : context.colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
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
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.goldSurface,
                  borderRadius: AppRadius.circular,
                ),
                child: Text(
                  l10n.currentStepLabel,
                  style: context.textStyles.labelSmall?.copyWith(
                    color: AppColors.goldDeep,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
