import 'package:field_service/features/admin/domain/entities/admin_account_status.dart';
import 'package:field_service/features/admin/domain/entities/managed_customer.dart';
import 'package:field_service/features/admin/domain/repositories/admin_repository.dart';

/// Use case: block / unblock / soft delete one customer.
///
/// A blocked customer can no longer be attached to a NEW job (the server
/// refuses it inside `create_job`), while every historical job, photo and
/// signature stays readable. The delete is always a SOFT delete.
class SetCustomerStatus {
  const SetCustomerStatus(this._repository);

  final AdminRepository _repository;

  Future<ManagedCustomer> call({
    required String customerId,
    required AdminAccountStatus status,
  }) => _repository.setCustomerStatus(customerId: customerId, status: status);
}
