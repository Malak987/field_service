import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/localization/locale_cubit.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Reusable language selector widget that switches between English (`en`) and
/// German (`de`) and persists the selection via [LocaleCubit].
class LanguageSwitcher extends StatelessWidget {
  const LanguageSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final LocaleCubit? localeCubit = context.read<LocaleCubit?>();
    final Locale activeLocale =
        context.watch<LocaleCubit?>()?.state ?? Localizations.localeOf(context);
    final AppLocalizations l10n = context.l10n;
    final bool isDark = context.isDarkMode;
    final Color borderColor = isDark
        ? AppColors.borderDark
        : AppColors.borderLight;
    final Color surfaceColor = isDark
        ? AppColors.cardDark
        : AppColors.cardLight;

    return Semantics(
      label: l10n.selectLanguage,
      child: Container(
        padding: const EdgeInsetsDirectional.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: AppRadius.controlDirectional,
          border: Border.all(
            color: borderColor,
            width: AppDimensions.borderWidth,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsetsDirectional.only(
                start: AppSpacing.sm,
                end: AppSpacing.xs,
              ),
              child: Icon(Icons.language_outlined, size: AppDimensions.iconSm),
            ),
            _LanguageOptionChip(
              label: l10n.languageEnglish,
              isSelected: activeLocale.languageCode == 'en',
              onTap: () => localeCubit?.setLocale(const Locale('en')),
            ),
            const SizedBox(width: AppSpacing.xxs),
            _LanguageOptionChip(
              label: l10n.languageGerman,
              isSelected: activeLocale.languageCode == 'de',
              onTap: () => localeCubit?.setLocale(const Locale('de')),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageOptionChip extends StatelessWidget {
  const _LanguageOptionChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = context.colors;

    return Material(
      color: isSelected ? colors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs + 2,
          ),
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? colors.onPrimary : colors.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
