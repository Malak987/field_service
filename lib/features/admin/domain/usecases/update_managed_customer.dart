import 'package:field_service/features/admin/domain/entities/managed_customer.dart';
import 'package:field_service/features/admin/domain/repositories/admin_repository.dart';

/// Use case: edit a customer's master data (never its lifecycle status).
class UpdateManagedCustomer {
  const UpdateManagedCustomer(this._repository);

  final AdminRepository _repository;

  Future<ManagedCustomer> call({
    required String customerId,
    required String name,
    required String address,
    String? phone,
    String? email,
    String? city,
    String? postalCode,
    String? notes,
  }) => _repository.updateCustomer(
    customerId: customerId,
    name: name,
    address: address,
    phone: phone,
    email: email,
    city: city,
    postalCode: postalCode,
    notes: notes,
  );
}
