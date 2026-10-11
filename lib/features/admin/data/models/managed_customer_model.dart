import 'package:field_service/features/admin/data/models/managed_employee_model.dart';
import 'package:field_service/features/admin/domain/entities/admin_account_status.dart';
import 'package:field_service/features/admin/domain/entities/managed_customer.dart';

/// Data-layer mapping of one `admin_list_customers()` /
/// `admin_create_customer()` / `admin_update_customer()` /
/// `admin_set_customer_status()` row.
///
/// Server column → entity field:
///
/// | Column           | Field           |
/// |------------------|-----------------|
/// | `id`             | [id]            |
/// | `name`           | [name]          |
/// | `phone`          | [phone]         |
/// | `email`          | [email]         |
/// | `address`        | [address]       |
/// | `city`           | [city]          |
/// | `postal_code`    | [postalCode]    |
/// | `notes`          | [notes]         |
/// | `account_status` | [status]        |
/// | `blocked_at`     | [blockedAt]     |
/// | `deleted_at`     | [deletedAt]     |
/// | `created_at`     | [createdAt]     |
/// | `updated_at`     | [updatedAt]     |
/// | `jobs_count`     | [jobsCount]     |
class ManagedCustomerModel extends ManagedCustomer {
  const ManagedCustomerModel({
    required super.id,
    required super.name,
    required super.address,
    super.phone,
    super.email,
    super.city,
    super.postalCode,
    super.notes,
    super.status,
    super.blockedAt,
    super.deletedAt,
    super.createdAt,
    super.updatedAt,
    super.jobsCount,
  });

  factory ManagedCustomerModel.fromRow(Map<String, dynamic> row) {
    return ManagedCustomerModel(
      id: row['id'] as String,
      name: row['name'] as String? ?? '',
      address: row['address'] as String? ?? '',
      phone: row['phone'] as String?,
      email: row['email'] as String?,
      city: row['city'] as String?,
      postalCode: row['postal_code'] as String?,
      notes: row['notes'] as String?,
      status: AdminAccountStatus.fromRemote(row['account_status'] as String?),
      blockedAt: parseNullableTimestamp(row['blocked_at']),
      deletedAt: parseNullableTimestamp(row['deleted_at']),
      createdAt: parseNullableTimestamp(row['created_at']),
      updatedAt: parseNullableTimestamp(row['updated_at']),
      jobsCount: _parseCount(row['jobs_count']),
    );
  }

  static int _parseCount(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}
