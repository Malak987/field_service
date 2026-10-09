import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/widgets/app_bottom_nav.dart';
import 'package:field_service/core/widgets/language_switcher.dart';
import 'package:field_service/features/authentication/domain/entities/app_user.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Account screen (route `/account`) — identity, language and sign-out for
/// BOTH roles.
///
/// Purely presentational over the existing [AuthenticationCubit] session:
/// it reads the authenticated [AppUser] and the shared language cubit, and
/// offers no business action besides the already-existing sign-out.
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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountTitle)),
      bottomNavigationBar: AppBottomNav(
        isAdmin: isAdmin,
        selectedIndex: isAdmin ? 3 : 2,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _IdentityCard(user: user),
              const SizedBox(height: AppSpacing.lg),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.selectLanguage,
                        style: context.textStyles.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const LanguageSwitcher(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxxl),
              FilledButton.icon(
                key: const Key('account_sign_out'),
                onPressed: isSigningOut
                    ? null
                    : () => context.read<AuthenticationCubit>().signOut(),
                icon: const Icon(
                  Icons.logout_outlined,
                  size: AppDimensions.iconMd,
                ),
                label: Text(l10n.logoutButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The identity card: avatar (initials of the real name or email), name,
/// e-mail, role badge and the employee code when the backend provides one.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.user});

  final AppUser? user;

  String get _displayName {
    final String? name = user?.name;
    if (name != null && name.trim().isNotEmpty) {
      return name.trim();
    }
    return user?.email ?? '';
  }

  String get _initials {
    final List<String> parts = _displayName
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppUser? user = this.user;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: <Widget>[
            Container(
              key: const Key('account_avatar'),
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primarySurface,
              ),
              alignment: Alignment.center,
              child: Text(
                _initials,
                style: context.textStyles.headlineMedium?.copyWith(
                  color: context.colors.primary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _displayName,
              textAlign: TextAlign.center,
              style: context.textStyles.titleLarge,
            ),
            if (user != null) ...<Widget>[
              if (user.email != _displayName) ...<Widget>[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  user.email,
                  textAlign: TextAlign.center,
                  style: context.textStyles.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.circular,
                      color: AppColors.goldSurface,
                    ),
                    child: Text(
                      user.isAdmin
                          ? l10n.roleAdminLabel
                          : l10n.roleTechnicianLabel,
                      style: context.textStyles.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.goldDeep,
                      ),
                    ),
                  ),
                  if ((user.employeeCode ?? '').isNotEmpty) ...<Widget>[
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      user.employeeCode!,
                      style: context.textStyles.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
