import 'package:field_service/features/jobs/domain/entities/accessible_customer.dart';

/// Data-layer mapping for one row returned by the
/// `technician_accessible_customers` RPC.
///
/// Kept in `features/jobs` (not `features/customers`): this is the
/// technician's narrow, job-scoped read path — never access to the
/// admin-only Customers feature.
class AccessibleCustomerModel extends AccessibleCustomer {
  const AccessibleCustomerModel({
    required super.id,
    required super.name,
    super.phone,
    super.address,
    super.city,
    super.postalCode,
  });

  /// Maps one PostgREST row of the RPC result set.
  ///
  /// The RPC returns only the six columns the picker displays; absent keys
  /// are treated as `null` rather than as an error.
  factory AccessibleCustomerModel.fromRpcRow(Map<String, dynamic> row) {
    return AccessibleCustomerModel(
      id: row['id'] as String,
      name: row['name'] as String,
      phone: row['phone'] as String?,
      address: row['address'] as String?,
      city: row['city'] as String?,
      postalCode: row['postal_code'] as String?,
    );
  }
}
