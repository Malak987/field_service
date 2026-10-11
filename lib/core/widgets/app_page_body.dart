import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      body: SafeArea(
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
