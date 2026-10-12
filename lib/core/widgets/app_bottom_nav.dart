import 'package:field_service/app/router/app_routes.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// One destination of the role-aware main navigation.
///
/// [location] is always an EXISTING route: the two category tabs open the jobs
/// list through its existing `?category=` query parameter, so the navigation
/// adds no route, no page and no second source of truth for the filter.
@immutable
class AppNavDestination {
  const AppNavDestination({
    required this.navKey,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.location,
  });

  /// Stable identity of the destination (`bottom_nav_home`, …).
  final Key navKey;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String location;
}

/// The role-aware destination sets — the single place where "what can this
/// role reach from the main navigation" is decided.
///
/// * **Administrator**: Home · Kitchen · Home Renovation · Account. The two
///   middle tabs are the job categories, which is how an administrator actually
///   reads the work; customer management stays on the dashboard tiles (and its
///   own route), because it is a management area, not a daily destination.
/// * **Technician**: Home · My Jobs · Account. Customer management is
///   deliberately absent for technicians — the `/customers` routes are refused
///   by the router guard regardless of this list.
abstract final class AppNavDestinations {
  static const String _kitchenLocation =
      '${AppRoutes.jobs}?category=${JobCategory.kitchenRenovation}';
  static const String _homeRenovationLocation =
      '${AppRoutes.jobs}?category=${JobCategory.homeRenovation}';

  /// Index of the account tab per role — the one destination both roles share.
  static int accountIndex({required bool isAdmin}) => isAdmin ? 3 : 2;

  /// Index of the jobs tab per role: the technician's single jobs tab, or the
  /// kitchen category tab for an administrator.
  static int jobsIndex({required bool isAdmin}) => 1;

  static List<AppNavDestination> of({
    required bool isAdmin,
    required AppLocalizations l10n,
  }) {
    final AppNavDestination home = AppNavDestination(
      navKey: const Key('bottom_nav_home'),
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: l10n.homeTabLabel,
      location: AppRoutes.root,
    );
    final AppNavDestination account = AppNavDestination(
      navKey: const Key('bottom_nav_account'),
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      label: l10n.accountTitle,
      location: AppRoutes.account,
    );

    if (!isAdmin) {
      return <AppNavDestination>[
        home,
        AppNavDestination(
          navKey: const Key('bottom_nav_my_jobs'),
          icon: Icons.event_note_outlined,
          selectedIcon: Icons.event_note_rounded,
          label: l10n.myJobsTitle,
          location: AppRoutes.jobs,
        ),
        account,
      ];
    }

    return <AppNavDestination>[
      home,
      AppNavDestination(
        navKey: const Key('bottom_nav_kitchen'),
        icon: Icons.kitchen_outlined,
        selectedIcon: Icons.kitchen_rounded,
        label: l10n.kitchenTabLabel,
        location: _kitchenLocation,
      ),
      AppNavDestination(
        navKey: const Key('bottom_nav_home_renovation'),
        icon: Icons.house_siding_outlined,
        selectedIcon: Icons.house_siding_rounded,
        label: l10n.homeRenovationTabLabel,
        location: _homeRenovationLocation,
      ),
      account,
    ];
  }

}

/// Which navigation a page shows, and which of its tabs is current.
///
/// [selectedIndex] is `null` when the page is not one of the destinations — a
/// management screen, or the unfiltered jobs list an administrator opened from
/// a dashboard tile. The bars render that state without highlighting a tab the
/// user is not looking at.
@immutable
class AppNavSpec {
  const AppNavSpec({required this.isAdmin, this.selectedIndex});

  final bool isAdmin;
  final int? selectedIndex;
}

/// The role-aware main navigation.
///
/// One destination set, two renderings: a [NavigationBar] on phones and a
/// [NavigationRail] on wide layouts (see `AppPageBody`, which owns the
/// breakpoint so no screen invents its own). Destinations navigate with
/// `context.go` — repeated taps never stack pages — and tapping the tab of the
/// page you are already on is a no-op.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.isAdmin,
    required this.selectedIndex,
  });

  /// Whether the authenticated employee is an admin (selects the 4-item admin
  /// bar; technicians get the 3-item bar).
  final bool isAdmin;

  /// Index of the highlighted destination, or `null` for "no tab is current".
  final int? selectedIndex;

  @override
  Widget build(BuildContext context) {
    final List<AppNavDestination> destinations = AppNavDestinations.of(
      isAdmin: isAdmin,
      l10n: context.l10n,
    );

    // `NavigationBar` always highlights one destination. When the current page
    // is not a tab, the highlight is neutralized through the theme instead of
    // pointing at a destination the user is not on.
    final bool highlight = selectedIndex != null;

    final NavigationBar bar = NavigationBar(
      selectedIndex: selectedIndex ?? 0,
      onDestinationSelected: (int index) =>
          _goTo(context, destinations[index]),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: <NavigationDestination>[
        for (final AppNavDestination destination in destinations)
          NavigationDestination(
            key: destination.navKey,
            icon: Icon(destination.icon),
            selectedIcon: Icon(destination.selectedIcon),
            label: destination.label,
          ),
      ],
    );

    if (highlight) {
      return bar;
    }

    final ThemeData theme = Theme.of(context);
    final Color idle = theme.colorScheme.onSurfaceVariant;
    // Keep the bar's own typography and only drop the "this one is current"
    // signal, so a page outside the tabs looks exactly like the others.
    final NavigationBarThemeData bars = theme.navigationBarTheme;
    final TextStyle? idleLabel = bars.labelTextStyle
        ?.resolve(<WidgetState>{})
        ?.copyWith(color: idle, fontWeight: FontWeight.w500);
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStatePropertyAll<IconThemeData>(
          IconThemeData(color: idle, size: AppDimensions.iconLg),
        ),
        labelTextStyle: WidgetStatePropertyAll<TextStyle?>(idleLabel),
      ),
      child: bar,
    );
  }

  /// Shared by the bar and the rail: one navigation rule, two renderings.
  static void _goTo(BuildContext context, AppNavDestination destination) {
    if (GoRouterState.of(context).uri.toString() != destination.location) {
      context.go(destination.location);
    }
  }
}

/// The wide-layout counterpart of [AppBottomNav]: the same destinations as a
/// leading rail, so the field screens keep their full width on a tablet or in
/// the browser while every main area stays one tap away.
class AppNavigationRail extends StatelessWidget {
  const AppNavigationRail({
    super.key,
    required this.isAdmin,
    required this.selectedIndex,
  });

  final bool isAdmin;
  final int? selectedIndex;

  @override
  Widget build(BuildContext context) {
    final List<AppNavDestination> destinations = AppNavDestinations.of(
      isAdmin: isAdmin,
      l10n: context.l10n,
    );

    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: (int index) =>
          AppBottomNav._goTo(context, destinations[index]),
      labelType: NavigationRailLabelType.all,
      groupAlignment: -0.9,
      // Wider than the 72px default so the longest label the app has
      // ("Home Renovation", "Haussanierung") wraps inside the rail instead of
      // being clipped.
      minWidth: 96,
      destinations: <NavigationRailDestination>[
        for (final AppNavDestination destination in destinations)
          NavigationRailDestination(
            icon: Icon(destination.icon, key: destination.navKey),
            selectedIcon: Icon(destination.selectedIcon),
            label: Text(
              destination.label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}
