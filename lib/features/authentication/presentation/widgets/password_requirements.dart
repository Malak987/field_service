import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/theme/app_text_styles.dart';
import 'package:field_service/core/utils/password_validator.dart';
import 'package:flutter/material.dart';

/// Live password requirement checklist driven by [PasswordValidator].
///
/// Listens to a [ValueListenable<TextEditingValue>] (the password controller)
/// so typing only rebuilds this checklist widget rather than the entire screen.
class PasswordRequirements extends StatelessWidget {
  const PasswordRequirements({
    required this.controller,
    this.policy = PasswordPolicy.standard,
    super.key,
  });

  final TextEditingController controller;
  final PasswordPolicy policy;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final bool isDark = context.isDarkMode;
    final Color borderColor = isDark
        ? AppColors.borderDark
        : AppColors.borderLight;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (BuildContext context, TextEditingValue value, Widget? _) {
        final PasswordValidationStatus status = PasswordValidator.evaluate(
          value.text,
          policy: policy,
        );

        return Container(
          padding: const EdgeInsetsDirectional.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadius.bannerDirectional,
            border: Border.all(
              color: borderColor,
              width: AppDimensions.borderWidth,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.passwordRequirementsTitle,
                style: context.textStyles.titleSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              _RequirementRow(
                label: l10n.passwordReqMinLength(policy.minLength),
                isMet: status.hasMinLength,
              ),
              if (policy.requireUppercase)
                _RequirementRow(
                  label: l10n.passwordReqUppercase,
                  isMet: status.hasUppercase,
                ),
              if (policy.requireLowercase)
                _RequirementRow(
                  label: l10n.passwordReqLowercase,
                  isMet: status.hasLowercase,
                ),
              if (policy.requireNumber)
                _RequirementRow(
                  label: l10n.passwordReqNumber,
                  isMet: status.hasNumber,
                ),
              if (policy.requireSpecialCharacter)
                _RequirementRow(
                  label: l10n.passwordReqSpecialChar,
                  isMet: status.hasSpecialCharacter,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RequirementRow extends StatelessWidget {
  const _RequirementRow({required this.label, required this.isMet});

  final String label;
  final bool isMet;

  @override
  Widget build(BuildContext context) {
    final Color activeColor = isMet
        ? AppColors.success
        : (context.isDarkMode
              ? AppColors.textSecondaryDark
              : AppColors.textSecondaryLight);

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Icon(
            isMet ? Icons.check_circle : Icons.radio_button_unchecked,
            size: AppDimensions.iconSm,
            color: activeColor,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: activeColor,
                fontWeight: isMet ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
