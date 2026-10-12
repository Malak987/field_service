import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The shared visual language for the three non-content states every list has:
/// loading, empty and failed.
///
/// Deliberately quiet. A state view is a pause in the screen, not a hero: one
/// restrained icon in a hairline circle, a short title, at most one line of
/// context, and — for failures — the retry action. All copy is passed in, so
/// each feature keeps its own real message and behaviour; only the frame is
/// shared.
class AppStateView extends StatelessWidget {
  const AppStateView({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.iconTint,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;

  /// Optional trailing action — the retry button for failures, a "create the
  /// first item" button for an empty list.
  final Widget? action;

  /// Overrides the neutral icon tint (used for failures only).
  final Color? iconTint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: context.colors.outlineVariant),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: AppDimensions.iconLg,
              color: iconTint ?? context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: context.textStyles.titleMedium,
          ),
          if (message != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: context.textStyles.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
          if (action != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xl),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Failure state: the only state view that is allowed colour, because a refusal
/// has to be noticed. Still no banner, no red surface — the icon carries it.
class AppErrorStateView extends StatelessWidget {
  const AppErrorStateView({
    required this.title,
    required this.onRetry,
    required this.retryLabel,
    this.message,
    this.icon = Icons.error_outline_rounded,
    super.key,
  });

  final String title;
  final VoidCallback onRetry;
  final String retryLabel;
  final String? message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: title,
      child: AppStateView(
        icon: icon,
        iconTint: context.colors.error,
        title: title,
        message: message,
        action: OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: AppDimensions.iconSm),
          label: Text(retryLabel),
        ),
      ),
    );
  }
}

/// Empty state — neutral by design. An empty list is not an error.
class AppEmptyStateView extends StatelessWidget {
  const AppEmptyStateView({
    required this.title,
    this.message,
    this.action,
    this.icon = Icons.inbox_outlined,
    super.key,
  });

  final String title;
  final String? message;
  final Widget? action;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppStateView(
      icon: icon,
      title: title,
      message: message,
      action: action,
    );
  }
}

/// Loading state. A single centred spinner with an accessible label — no
/// skeleton, because every list here resolves from a local mirror in a few
/// milliseconds and a shimmer would only add motion.
class AppLoadingStateView extends StatelessWidget {
  const AppLoadingStateView({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: AppDimensions.spinnerStrokeWidth,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                label,
                style: context.textStyles.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
