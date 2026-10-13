import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_radius.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/jobs/domain/entities/accessible_customer.dart';
import 'package:flutter/material.dart';

/// The "existing customer" selector tile of the technician form.
///
/// Same affordance as the customer selector of the admin Create Job screen
/// (a tappable summary tile, never a free-text field): the technician picks
/// from the customers the server says they may work for.
class AccessibleCustomerTile extends StatelessWidget {
  const AccessibleCustomerTile({
    super.key,
    required this.customer,
    required this.hasError,
    required this.onTap,
  });

  /// The chosen customer, or `null` before a selection.
  final AccessibleCustomer? customer;

  /// Renders the error border (a submit attempt without a selection).
  final bool hasError;

  /// Opens the picker; `null` disables the tile (submission in flight).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final bool selected = customer != null;
    final Color borderColor = hasError
        ? context.colors.error
        : selected
        ? AppColors.primary
        : context.colors.outlineVariant;

    return Semantics(
      button: true,
      label: customer?.name ?? l10n.selectCustomerLabel,
      child: Material(
        color: selected ? AppColors.primarySurface : context.colors.surface,
        borderRadius: AppRadius.control,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.control,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppDimensions.minTapTarget + AppSpacing.lg,
            ),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              borderRadius: AppRadius.control,
              border: Border.all(
                color: borderColor,
                width: selected ? AppDimensions.focusedBorderWidth : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: AppDimensions.buttonHeightCompact,
                  height: AppDimensions.buttonHeightCompact,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.goldSurface,
                    borderRadius: AppRadius.banner,
                  ),
                  child: const Icon(
                    Icons.person_search_outlined,
                    color: AppColors.goldDeep,
                    size: AppDimensions.iconMd,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        customer?.name ?? l10n.selectCustomerLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.bodyLarge?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      if (customer != null && customer!.subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xxs),
                          child: Text(
                            customer!.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textStyles.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.expand_more_rounded,
                  color: selected
                      ? AppColors.primary
                      : context.colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet picker over the customers the technician may work for.
///
/// Returns the chosen [AccessibleCustomer] or `null` when dismissed. The
/// caller owns loading/error/empty presentation (it knows the cubit state);
/// this widget only filters and returns a selection.
class AccessibleCustomerPicker extends StatefulWidget {
  const AccessibleCustomerPicker({
    super.key,
    required this.customers,
    this.selectedId,
  });

  final List<AccessibleCustomer> customers;
  final String? selectedId;

  @override
  State<AccessibleCustomerPicker> createState() =>
      _AccessibleCustomerPickerState();
}

class _AccessibleCustomerPickerState extends State<AccessibleCustomerPicker> {
  String _query = '';

  List<AccessibleCustomer> get _visible {
    final String needle = _query.trim().toLowerCase();
    if (needle.isEmpty) {
      return widget.customers;
    }
    return widget.customers.where((AccessibleCustomer customer) {
      return customer.name.toLowerCase().contains(needle) ||
          (customer.phone ?? '').toLowerCase().contains(needle) ||
          (customer.address ?? '').toLowerCase().contains(needle) ||
          (customer.city ?? '').toLowerCase().contains(needle);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final MediaQueryData media = MediaQuery.of(context);
    final double bottomInset = media.viewInsets.bottom;
    final List<AccessibleCustomer> visible = _visible;

    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: AppSpacing.lg,
        end: AppSpacing.lg,
        top: AppSpacing.sm,
        bottom: bottomInset + AppSpacing.lg,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppDimensions.contentMaxWidth,
        ),
        child: SizedBox(
          height: (media.size.height - bottomInset) * .7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                l10n.technicianSelectExistingCustomerTitle,
                style: context.textStyles.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('technician_customer_search'),
                autofocus: true,
                onChanged: (String value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: l10n.searchCustomersHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: visible.isEmpty
                    ? _PickerEmptyState(
                        title: _query.trim().isEmpty
                            ? l10n.customersEmptyTitle
                            : l10n.customersNoResultsTitle,
                      )
                    : ListView.separated(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: visible.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (BuildContext context, int index) {
                          final AccessibleCustomer customer = visible.elementAt(
                            index,
                          );
                          return _PickerCustomerRow(
                            key: Key(
                              'technician_customer_option_${customer.id}',
                            ),
                            customer: customer,
                            selected: widget.selectedId == customer.id,
                            onTap: () => Navigator.of(context).pop(customer),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerCustomerRow extends StatelessWidget {
  const _PickerCustomerRow({
    super.key,
    required this.customer,
    required this.selected,
    required this.onTap,
  });

  final AccessibleCustomer customer;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primarySurface : context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(
          color: selected ? AppColors.primary : context.colors.outlineVariant,
          width: selected ? AppDimensions.focusedBorderWidth : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              Container(
                width: AppDimensions.buttonHeightCompact,
                height: AppDimensions.buttonHeightCompact,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.goldSurface,
                  borderRadius: AppRadius.banner,
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: AppColors.goldDeep,
                  size: AppDimensions.iconMd,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (customer.subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xxs),
                        child: Text(
                          customer.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: selected
                    ? AppColors.primary
                    : context.colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerEmptyState extends StatelessWidget {
  const _PickerEmptyState({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.person_search_outlined,
              size: AppDimensions.iconXl,
              color: AppColors.goldDeep,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.textStyles.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
