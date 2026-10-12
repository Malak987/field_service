import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// One figure on a dashboard: a number, its label and a colour that ties it to
/// the status it counts.
///
/// A tile, not a banner. The number carries the weight; the accent is a thin
/// rule on the leading edge plus the dot in the label row, so four of them side
/// by side stay comparable instead of becoming four competing coloured blocks.
///
/// The number is always a real count passed in by the caller. This widget never
/// defaults to `0`: a caller without data renders nothing at all rather than a
/// tile that claims a figure it does not have.
class AppStatTile extends StatelessWidget {
  const AppStatTile({
    required this.statKey,
    required this.label,
    required this.value,
    required this.accent,
    this.onTap,
    super.key,
  });

  /// Lives on the tile itself so a test can read one figure without depending
  /// on the layout around it.
  final Key statKey;

  final String label;

  /// The counted value. Already an `int` — formatting is the caller's business.
  final int value;

  /// The status colour this figure belongs to (same palette as the status
  /// badges), used for the leading rule and the label dot.
  final Color accent;

  /// Optional drill-down (usually "show me the jobs in this state").
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget content = Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // The figure. Deliberately the largest thing in the tile.
          Text(
            '$value',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.headlineSmall?.copyWith(
              color: context.colors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    final Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: AppRadius.card,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(width: 3, color: accent),
              Expanded(child: content),
            ],
          ),
        ),
      ),
    );

    if (onTap == null) {
      return Semantics(
        key: statKey,
        container: true,
        label: '$label: $value',
        child: surface,
      );
    }

    // A Material, not a decorated Container: the splash an InkWell paints lands
    // on the nearest Material ancestor, so behind a plain Container the press
    // feedback would be drawn underneath this surface and never show.
    return Semantics(
      key: statKey,
      container: true,
      button: true,
      label: '$label: $value',
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: surface),
      ),
    );
  }
}

/// Lays [AppStatTile]s out responsively: two columns on a phone, four once the
/// viewport reaches the shared tablet breakpoint.
///
/// `Wrap` was rejected because it cannot give the tiles equal width, and equal
/// width is what makes the four figures comparable. The breakpoint comes from
/// [AppDimensions] so this screen does not invent its own threshold.
///
/// Each row is wrapped in [IntrinsicHeight]. That is a correctness matter, not
/// decoration: a `Row` with [CrossAxisAlignment.stretch] inside a scroll view
/// receives an unbounded height, and stretching a child against infinity trips
/// a framework assert. This is the same pairing the job cards already use.
class AppStatGrid extends StatelessWidget {
  const AppStatGrid({
    required this.children,
    this.columnsOnPhone = 2,
    this.columnsOnWide = 4,
    super.key,
  });

  final List<Widget> children;
  final int columnsOnPhone;
  final int columnsOnWide;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final int columns = width >= AppDimensions.tabletBreakpoint
        ? columnsOnWide
        : columnsOnPhone;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < children.length; i += columns)
          Padding(
            padding: EdgeInsetsDirectional.only(
              bottom: i + columns < children.length ? AppSpacing.sm : 0,
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int c = 0; c < columns; c++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(
                          end: c < columns - 1 ? AppSpacing.sm : 0,
                        ),
                        // A short row is padded out with an empty box so the
                        // columns keep their width and the grid never reflows
                        // when a screen passes an odd number of tiles.
                        child: i + c < children.length
                            ? children[i + c]
                            : const SizedBox.shrink(),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
