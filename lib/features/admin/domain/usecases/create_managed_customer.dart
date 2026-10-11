import 'package:field_service/features/admin/domain/entities/managed_customer.dart';
import 'package:field_service/features/admin/domain/repositories/admin_repository.dart';

/// Use case: create a customer through the management RPC (online path).
///
/// The offline-first create path of the Customers feature is untouched; this
/// use case backs the admin management screen, where the server validates the
/// data and stamps `created_at` / `updated_at` itself.
class CreateManagedCustomer {
  const CreateManagedCustomer(this._repository);

  final AdminRepository _repository;

  Future<ManagedCustomer> call({
    required String name,
    required String address,
    String? phone,
    String? email,
    String? city,
    String? postalCode,
    String? notes,
  }) => _repository.createCustomer(
    name: name,
    address: address,
    phone: phone,
    email: email,
    city: city,
    postalCode: postalCode,
    notes: notes,
  );
}
