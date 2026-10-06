import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/widgets/home_navigation_tile.dart';
import 'package:field_service/core/widgets/language_switcher.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class AdminHomePage extends StatelessWidget {
  const AdminHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final bool isLoading = context.select<AuthenticationCubit, bool>(
      (AuthenticationCubit cubit) => cubit.state.isLoading,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminDashboardTitle),
        actions: <Widget>[
          const Padding(
            padding: EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.sm),
            child: Center(child: LanguageSwitcher()),
          ),
          IconButton(
            tooltip: l10n.logoutButton,
            icon: const Icon(Icons.logout_outlined, size: AppDimensions.iconMd),
            onPressed: isLoading
                ? null
                : () => context.read<AuthenticationCubit>().signOut(),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: Center(
        child: Padding(
          padding: AppSpacing.pagePadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                l10n.welcomeAdmin,
                textAlign: TextAlign.center,
                style: context.textStyles.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xl),
              // The admin's main navigation: one reusable tile per feature
              // that actually exists. Jobs replaces the stack (`go`);
              // Customers is pushed so its Back button returns here.
              HomeNavigationTile(
                key: const Key('nav_jobs'),
                icon: Icons.event_note_outlined,
                label: l10n.viewJobsButton,
                onTap: () => context.go(AppRoutes.jobs),
              ),
              const SizedBox(height: AppSpacing.md),
              HomeNavigationTile(
                key: const Key('nav_customers'),
                icon: Icons.people_outline,
                label: l10n.customersTitle,
                onTap: () => context.push(AppRoutes.customers),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
