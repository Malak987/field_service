import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/customers/presentation/widgets/customer_sync_status.dart';
import 'package:flutter/material.dart';

/// One card in the customers list.
///
/// Purely presentational (same rule as `JobsListItem`): the address line is
/// assembled from the entity, the sync chip reflects the local row state,
/// and navigation is injected via [onTap] — no router inside.
class CustomerCard extends StatelessWidget {
  const CustomerCard({
    super.key,
    required this.customer,
    required this.onTap,
  });

  final Customer customer;

  /// Called when the card is tapped (navigates to the details route).
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String cityLine = customer.cityLine;
    final String addressLine = cityLine.isEmpty
        ? customer.address
        : '${customer.address}, $cityLine';

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  CustomerSyncStatusChip(status: customer.syncStatus),
                ],
              ),
              if (customer.phone != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.phone_outlined,
                      size: AppDimensions.iconSm,
                      color: context.colors.outline,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        customer.phone!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.place_outlined,
                      size: AppDimensions.iconSm,
                      color: context.colors.outline,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      addressLine,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
