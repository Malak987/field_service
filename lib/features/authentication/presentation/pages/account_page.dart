import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/sync/sync_status.dart';
import 'package:field_service/core/sync/sync_status_cubit.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/widgets/app_bottom_nav.dart';
import 'package:field_service/core/widgets/app_page_body.dart';
import 'package:field_service/core/widgets/app_section_header.dart';
import 'package:field_service/core/widgets/app_standard_page_header.dart';
import 'package:field_service/core/widgets/app_sync_status_badge.dart';
import 'package:field_service/core/widgets/language_switcher.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Account screen (route `/account`) — identity, language, sync visibility and
/// sign-out for both authenticated roles.
///
/// It is purely presentational over the existing [AuthenticationCubit] session
/// and shared locale/sync state. No profile data is fetched, edited or invented
/// here; all facts come from the already-authenticated [AppUser].
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppUser? user = context.select<AuthenticationCubit, AppUser?>(
      (AuthenticationCubit cubit) => cubit.state.user,
    );
    final bool isAdmin = user?.isAdmin ?? false;
    final bool isSigningOut = context.select<AuthenticationCubit, bool>(
      (AuthenticationCubit cubit) => cubit.state.isLoading,
    );

    return BlocProvider<SyncStatusCubit>(
      // The offline engine's own state — the same source of truth used by the
      // existing customers header and account surface.
      create: (_) => sl<SyncStatusCubit>(),
      child: AppPageBody(
        // The logo-led header below is the page identity. Keeping the app bar
        // as quiet navigation chrome avoids repeating the title on a phone.
        appBar: AppBar(),
        responsivePadding: true,
        navigation: AppNavSpec(
          isAdmin: isAdmin,
          selectedIndex: AppNavDestinations.accountIndex(isAdmin: isAdmin),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _AccountHeader(
              title: l10n.accountTitle,
              subtitle: l10n.accountSettingsTooltip,
            ),
            const SizedBox(height: AppSpacing.xxl),
            _ProfilePanel(user: user),
            const SizedBox(height: AppSpacing.xxl),
            AppSectionHeader(title: l10n.selectLanguage),
            const SizedBox(height: AppSpacing.md),
            const _LanguagePreferencePanel(),
            const SizedBox(height: AppSpacing.xxl),
            AppSectionHeader(title: l10n.syncStatusTitle),
            const SizedBox(height: AppSpacing.md),
            const _SyncStatusPanel(),
            const SizedBox(height: AppSpacing.xxl),
            _SignOutPanel(isSigningOut: isSigningOut),
          ],
        ),
      ),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => AppStandardPageHeader(
    logoAssetName: AuthLogo.assetName,
    title: title,
    subtitle: subtitle,
  );
}

/// Real account facts only: the authenticated employee name, email, role and
/// employee code when the session contains them. A missing name falls back to
/// the actual email; a missing session renders a neutral person icon rather
/// than an invented identity.
class _ProfilePanel extends StatelessWidget {
  const _ProfilePanel({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppUser? user = this.user;
    final String displayName = _displayName(user);
    final String initials = _initials(displayName);
    final String roleLabel = _roleLabel(l10n, user);
    final String employeeCode = user?.employeeCode?.trim() ?? '';
    final String realName = user?.name?.trim() ?? '';
    final String email = user?.email.trim() ?? '';

    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  key: const Key('account_avatar'),
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(
                    color: AppColors.primarySurface,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: initials.isEmpty
                      ? const Icon(
                          Icons.person_outline_rounded,
                          size: AppDimensions.iconLg,
                          color: AppColors.primary,
                        )
                      : Text(
                          initials,
                          style: context.textStyles.titleLarge?.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (displayName.isNotEmpty)
                        Text(
                          displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.titleLarge,
                        ),
                      if (roleLabel.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            _RoleBadge(label: roleLabel),
                            if (employeeCode.isNotEmpty)
                              _EmployeeCodeBadge(code: employeeCode),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (realName.isNotEmpty || email.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              Divider(height: 1, color: context.colors.outlineVariant),
              const SizedBox(height: AppSpacing.lg),
              if (realName.isNotEmpty)
                _ProfileDetailRow(
                  icon: Icons.person_outline_rounded,
                  label: l10n.fullNameLabel,
                  value: realName,
                ),
              if (realName.isNotEmpty && email.isNotEmpty)
                const SizedBox(height: AppSpacing.md),
              if (email.isNotEmpty)
                _ProfileDetailRow(
                  icon: Icons.mail_outline_rounded,
                  label: l10n.emailLabel,
                  value: email,
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _displayName(AppUser? user) {
    final String name = user?.name?.trim() ?? '';
    if (name.isNotEmpty) {
      return name;
    }
    return user?.email.trim() ?? '';
  }

  String _initials(String value) {
    final List<String> parts = value
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '';
    }
    return parts
        .take(2)
        .map((String part) => part[0])
        .join()
        .toUpperCase();
  }

  String _roleLabel(AppLocalizations l10n, AppUser? user) {
    if (user == null) {
      return '';
    }
    if (user.isAdmin) {
      return l10n.roleAdminLabel;
    }
    if (user.isTechnician) {
      return l10n.roleTechnicianLabel;
    }
    return user.role;
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: AppColors.goldSurface,
        borderRadius: AppRadius.circular,
      ),
      child: Text(
        label,
        style: context.textStyles.labelSmall?.copyWith(
          color: AppColors.goldDeep,
        ),
      ),
    );
  }
}

class _EmployeeCodeBadge extends StatelessWidget {
  const _EmployeeCodeBadge({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: AppRadius.circular,
          border: Border.all(color: context.colors.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.badge_outlined,
              size: AppDimensions.iconSm,
              color: context.colors.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileDetailRow extends StatelessWidget {
  const _ProfileDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: AppDimensions.buttonHeightCompact,
          height: AppDimensions.buttonHeightCompact,
          decoration: const BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: AppRadius.banner,
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: AppDimensions.iconMd, color: AppColors.primary),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: context.textStyles.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(value, style: context.textStyles.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _LanguagePreferencePanel extends StatelessWidget {
  const _LanguagePreferencePanel();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget switcher = const LanguageSwitcher();
            final Widget description = Text(
              l10n.selectLanguage,
              style: context.textStyles.titleSmall,
            );

            if (constraints.maxWidth < 500) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _SectionIcon(icon: Icons.language_outlined),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: description),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: switcher,
                  ),
                ],
              );
            }

            return Row(
              children: <Widget>[
                _SectionIcon(icon: Icons.language_outlined),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: description),
                const SizedBox(width: AppSpacing.md),
                switcher,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SyncStatusPanel extends StatelessWidget {
  const _SyncStatusPanel();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionIcon(icon: Icons.cloud_outlined),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(l10n.syncStatusTitle, style: context.textStyles.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  BlocBuilder<SyncStatusCubit, SyncHealth>(
                    builder: (BuildContext context, SyncHealth health) =>
                        AppSyncStatusBadge(health: health, filled: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionIcon extends StatelessWidget {
  const _SectionIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppDimensions.buttonHeightCompact,
      height: AppDimensions.buttonHeightCompact,
      decoration: const BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: AppRadius.banner,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: AppDimensions.iconMd, color: AppColors.primary),
    );
  }
}

class _SignOutPanel extends StatelessWidget {
  const _SignOutPanel({required this.isSigningOut});

  final bool isSigningOut;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('account_sign_out'),
            onPressed: isSigningOut
                ? null
                : () => context.read<AuthenticationCubit>().signOut(),
            icon: isSigningOut
                ? const SizedBox(
                    width: AppDimensions.iconSm,
                    height: AppDimensions.iconSm,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.logout_outlined,
                    size: AppDimensions.iconMd,
                  ),
            label: Text(l10n.logoutButton),
          ),
        ),
      ),
    );
  }
}
