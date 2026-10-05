import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/customers/domain/repositories/customers_repository.dart';

/// Use case: create a customer offline-first.
///
/// Role policy (admins create, technicians do not) is enforced where the app
/// already reads the role (UI) and on the server by RLS — the authoritative
/// boundary. This use case stays role-free on purpose, mirroring `GetJobs`.
class CreateCustomer {
  const CreateCustomer(this._repository);

  final CustomersRepository _repository;

  Future<Customer> call({
    required String name,
    required String address,
    String? phone,
    String? email,
    String? city,
    String? postalCode,
    String? notes,
  }) {
    return _repository.createCustomer(
      name: name,
      address: address,
      phone: phone,
      email: email,
      city: city,
      postalCode: postalCode,
      notes: notes,
    );
  }
}
