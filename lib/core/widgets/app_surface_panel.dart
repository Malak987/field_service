import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The one surface rows and panels are drawn on.
///
/// A [Material] — not a decorated `Container` — so every [InkWell] or
/// [ListTile] inside it paints its splash on the white panel the user can see
/// instead of on the cream canvas underneath. It carries the app's card
/// treatment (white fill, hairline border, 12px radius) and, with
/// [divideRows], the hairline rhythm that makes a stack of rows read as one
/// list rather than as a pile of cards.
///
/// Every screen that shows rows uses this widget, so a row can move between the
/// jobs list, a dashboard and a management screen without changing how it
/// looks or where its ink lands.
class AppSurfacePanel extends StatelessWidget {
  const AppSurfacePanel({
    required this.children,
    this.divideRows = true,
    this.padding,
    super.key,
  });

  final List<Widget> children;

  /// Draw a hairline between consecutive rows (the default). Turn it off when
  /// the children already carry their own separation.
  final bool divideRows;

  /// Padding around the whole panel. Individual rows keep their own padding.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Widget column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int index = 0; index < children.length; index++) ...<Widget>[
          if (divideRows && index > 0)
            Divider(
              height: 1,
              thickness: 1,
              indent: AppSpacing.lg,
              color: colors.outlineVariant,
            ),
          children[index],
        ],
      ],
    );

    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: padding == null
          ? column
          : Padding(padding: padding!, child: column),
    );
  }
}
