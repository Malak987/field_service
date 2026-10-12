import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/core/widgets/app_bottom_nav.dart';
import 'package:flutter/material.dart';

/// The one place where the role-aware navigation is turned into a layout.
///
/// * Below [AppDimensions.desktopBreakpoint] the destinations are a
///   [NavigationBar] pinned to the bottom, where a thumb reaches on a phone.
/// * From that breakpoint up the SAME destinations lead the page as a
///   [NavigationRail], which is what a browser or a tablet expects, and the
///   page keeps its full height for content.
///
/// Screens that scroll on their own (a list that keeps its filters pinned, a
/// canvas) use this widget directly with their own body; every other screen
/// wants [AppPageBody], which adds the standard scroll shell around it. Because
/// the decision lives here, no screen invents a second breakpoint and no two
/// screens can disagree about when the rail appears.
class AppNavigationScaffold extends StatelessWidget {
  const AppNavigationScaffold({
    required this.child,
    this.navigation,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    super.key,
  }) : assert(
         navigation == null || bottomNavigationBar == null,
         'navigation and bottomNavigationBar are two answers to the same '
         'question — pass one of them',
       );

  final Widget child;

  /// The main area this screen belongs to. When `null` the screen is not part
  /// of the main navigation (a form, a details page, a dialog route).
  final AppNavSpec? navigation;

  final PreferredSizeWidget? appBar;

  /// Only for screens outside the main navigation that need a bottom bar of
  /// their own. Mutually exclusive with [navigation].
  final Widget? bottomNavigationBar;

  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final AppNavSpec? navigation = this.navigation;

    if (navigation == null) {
      return Scaffold(
        appBar: appBar,
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
        body: child,
      );
    }

    // One breakpoint for the whole app. See the class doc.
    final bool useRail =
        MediaQuery.sizeOf(context).width >= AppDimensions.desktopBreakpoint;

    return Scaffold(
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: useRail
          ? null
          : AppBottomNav(
              isAdmin: navigation.isAdmin,
              selectedIndex: navigation.selectedIndex,
            ),
      body: useRail
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppNavigationRail(
                  isAdmin: navigation.isAdmin,
                  selectedIndex: navigation.selectedIndex,
                ),
                VerticalDivider(
                  width: AppDimensions.borderWidth,
                  thickness: AppDimensions.borderWidth,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                Expanded(child: child),
              ],
            )
          : child,
    );
  }
}

/// The scroll shell shared by every authenticated screen.
///
/// One place where the responsive rules live, so a screen never invents its
/// own thresholds:
///
/// * `SafeArea` — system insets and the gesture bar are respected everywhere.
/// * Content is capped at [AppDimensions.contentMaxWidth] and centred, so a
///   form on a tablet does not become a 1200px-wide text field. Data-dense
///   admin screens pass [wide] to get [AppDimensions.wideContentMaxWidth].
/// * On a phone the cap is never reached, so nothing changes there — the same
///   widget serves 320px and 1600px.
/// * `keyboardDismissBehavior.onDrag` — a technician scrolling a long job list
///   with a dirty glove dismisses the keyboard instead of hunting for the
///   close button.
/// * [navigation] — the main area's role-aware navigation, rendered by
///   [AppNavigationScaffold]. Screens that are not main areas simply omit it.
///
/// Screens that manage their own scrolling (a `CustomScrollView` with a pinned
/// header, a `NestedScrollView`) keep doing so; this is for the common case.
class AppPageBody extends StatelessWidget {
  const AppPageBody({
    required this.child,
    this.appBar,
    this.wide = false,
    this.padding,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.navigation,
    super.key,
  });

  final Widget child;

  /// The screen's app bar. Passing it here (instead of nesting a second
  /// `Scaffold`) keeps one Material surface per screen.
  final PreferredSizeWidget? appBar;

  /// Use the wider content cap — for management lists and tables.
  final bool wide;

  /// Overrides the standard page padding.
  final EdgeInsetsGeometry? padding;

  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;

  /// The role-aware main navigation this screen belongs to, when it is one of
  /// the main areas.
  final AppNavSpec? navigation;

  @override
  Widget build(BuildContext context) {
    return AppNavigationScaffold(
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      navigation: navigation,
      child: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: padding ?? AppSpacing.pagePaddingCompact,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: wide
                    ? AppDimensions.wideContentMaxWidth
                    : AppDimensions.contentMaxWidth,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Width cap for list and detail content on tablets and wide desktop windows.
///
/// A 1400px-wide job list of full-bleed rows is unreadable — the eye has to
/// travel the whole viewport to get from a job number to its status. Content is
/// capped at [AppDimensions.wideContentMaxWidth] and centred, which is the same
/// breakpoint the form screens already use, so a tablet reads consistently
/// across the app. On a phone this is a no-op.
class AppContentWidth extends StatelessWidget {
  const AppContentWidth({super.key, required this.child, this.maxWidth});

  final Widget child;

  /// Defaults to the wide-content breakpoint; pass [AppDimensions.contentMaxWidth]
  /// for narrower reading columns.
  final double? maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth ?? AppDimensions.wideContentMaxWidth,
      ),
      child: child,
    ),
  );
}
