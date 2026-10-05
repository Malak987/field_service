import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/widgets/language_switcher.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class TechnicianHomePage extends StatelessWidget {
  const TechnicianHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.technicianHomeTitle),
        actions: <Widget>[
          const Padding(
            padding: EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.sm),
            child: Center(child: LanguageSwitcher()),
          ),
          IconButton(
            tooltip: l10n.logoutButton,
            icon: const Icon(
              Icons.logout_outlined,
              size: AppDimensions.iconMd,
            ),
            onPressed: () {
              context.read<AuthenticationCubit?>()?.signOut();
            },
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
                l10n.welcomeTechnician,
                textAlign: TextAlign.center,
                style: context.textStyles.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: () {
                  context.go(AppRoutes.jobs);
                },
                icon: const Icon(
                  Icons.event_note_outlined,
                  size: AppDimensions.iconMd,
                ),
                label: Text(l10n.viewJobsButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
