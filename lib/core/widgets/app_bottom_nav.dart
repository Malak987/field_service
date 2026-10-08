import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The role-aware bottom navigation shared by the main screens (home,
/// jobs list, account).
///
/// Destinations navigate with `context.go` — repeated taps never stack
/// pages, and every destination is an EXISTING route (the `/customers`
/// area is deliberately absent here and additionally refused by the router
/// guard for technicians). The widget carries no role logic of its own
/// beyond picking one of the two fixed destination sets passed by the
/// calling page, which already knows the authenticated role.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.isAdmin,
    required this.selectedIndex,
  });

  /// Whether the authenticated employee is an admin (selects the 4-item
  /// admin bar; technicians get the 3-item bar).
  final bool isAdmin;

  /// Index of the highlighted destination within the role's bar.
  final int selectedIndex;

  /// Jobs-list deep links used by the admin category tabs.
  static const String kitchenJobsLocation =
      '${AppRoutes.jobs}?category=${JobCategory.kitchenRenovation}';
  static const String homeRenovationJobsLocation =
      '${AppRoutes.jobs}?category=${JobCategory.homeRenovation}';

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    final List<NavigationDestination> destinations = isAdmin
        ? <NavigationDestination>[
            NavigationDestination(
              key: const Key('bottom_nav_home'),
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: l10n.homeTabLabel,
            ),
            NavigationDestination(
              key: const Key('bottom_nav_kitchen'),
              icon: const Icon(Icons.kitchen_outlined),
              selectedIcon: const Icon(Icons.kitchen_rounded),
              label: l10n.kitchenTabLabel,
            ),
            NavigationDestination(
              key: const Key('bottom_nav_home_renovation'),
              icon: const Icon(Icons.house_siding_outlined),
              selectedIcon: const Icon(Icons.house_siding_rounded),
              label: l10n.homeRenovationTabLabel,
            ),
            NavigationDestination(
              key: const Key('bottom_nav_account'),
              icon: const Icon(Icons.person_outline_rounded),
              selectedIcon: const Icon(Icons.person_rounded),
              label: l10n.accountTitle,
            ),
          ]
        : <NavigationDestination>[
            NavigationDestination(
              key: const Key('bottom_nav_home'),
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: l10n.homeTabLabel,
            ),
            NavigationDestination(
              key: const Key('bottom_nav_my_jobs'),
              icon: const Icon(Icons.event_note_outlined),
              selectedIcon: const Icon(Icons.event_note_rounded),
              label: l10n.myJobsTitle,
            ),
            NavigationDestination(
              key: const Key('bottom_nav_account'),
              icon: const Icon(Icons.person_outline_rounded),
              selectedIcon: const Icon(Icons.person_rounded),
              label: l10n.accountTitle,
            ),
          ];

    final List<String> locations = isAdmin
        ? const <String>[
            AppRoutes.root,
            kitchenJobsLocation,
            homeRenovationJobsLocation,
            AppRoutes.account,
          ]
        : const <String>[AppRoutes.root, AppRoutes.jobs, AppRoutes.account];

    return NavigationBar(
      selectedIndex: selectedIndex.clamp(0, destinations.length - 1),
      onDestinationSelected: (int index) {
        final String location = locations[index];
        // Tapping the current tab is a no-op (never re-pushes).
        if (GoRouterState.of(context).uri.toString() != location) {
          context.go(location);
        }
      },
      destinations: destinations,
    );
  }
}
