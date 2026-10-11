import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
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
    final Color borderColor = hasError
        ? context.colors.error
        : context.colors.outlineVariant;

    return Material(
      color: context.colors.surface,
      borderRadius: AppRadius.control,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.control,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.control,
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.person_search_outlined, color: context.colors.primary),
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
                        fontWeight: customer == null
                            ? FontWeight.normal
                            : FontWeight.w600,
                      ),
                    ),
                    if (customer != null && customer!.subtitle.isNotEmpty)
                      Text(
                        customer!.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                color: context.colors.onSurfaceVariant,
              ),
            ],
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
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        _query.trim().isEmpty
                            ? l10n.customersEmptyTitle
                            : l10n.customersNoResultsTitle,
                      ),
                    )
                  : ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final AccessibleCustomer customer = visible.elementAt(
                          index,
                        );
                        return ListTile(
                          key: Key('technician_customer_option_${customer.id}'),
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          title: Text(
                            customer.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: customer.subtitle.isEmpty
                              ? null
                              : Text(
                                  customer.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: widget.selectedId == customer.id
                              ? Icon(
                                  Icons.check_circle,
                                  color: context.colors.primary,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(customer),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
