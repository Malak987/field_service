import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/theme/app_text_styles.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_logo.dart';
import 'package:flutter/material.dart';

/// Displays the application brand, logo, screen title, and descriptive subtitle
/// at the top of an authentication screen.
class AuthHeader extends StatelessWidget {
  const AuthHeader({
    required this.title,
    required this.subtitle,
    this.icon = Icons.handyman_outlined,
    this.showBrandTitle = true,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool showBrandTitle;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ColorScheme colors = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AuthLogo(icon: icon),
        const SizedBox(height: AppSpacing.lg),
        if (showBrandTitle) ...<Widget>[
          Text(
            l10n.appName.toUpperCase(),
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Text(
          title,
          textAlign: TextAlign.center,
          style: context.textStyles.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: context.textStyles.bodyMedium,
        ),
      ],
    );
  }
}
