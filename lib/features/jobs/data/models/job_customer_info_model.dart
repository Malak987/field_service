import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';

/// Data-layer mapping for one row returned by the `get_job_customer` RPC.
///
/// Kept in `features/jobs` (not `features/customers`): this is the per-job
/// read path for Job Details, never access to the Customers feature.
class JobCustomerInfoModel extends JobCustomerInfo {
  const JobCustomerInfoModel({
    required super.name,
    super.phone,
    super.address,
    super.city,
    super.postalCode,
  });

  /// Maps one PostgREST row of the RPC result set.
  ///
  /// The RPC returns only the five display columns, so absent keys are
  /// treated as `null` rather than as an error.
  factory JobCustomerInfoModel.fromRpcRow(Map<String, dynamic> row) {
    return JobCustomerInfoModel(
      name: row['name'] as String,
      phone: row['phone'] as String?,
      address: row['address'] as String?,
      city: row['city'] as String?,
      postalCode: row['postal_code'] as String?,
    );
  }
}
