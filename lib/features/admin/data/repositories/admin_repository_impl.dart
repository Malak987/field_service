import 'package:field_service/features/admin/data/datasources/admin_remote_data_source.dart';
import 'package:field_service/features/admin/domain/entities/admin_account_status.dart';
import 'package:field_service/features/admin/domain/entities/managed_customer.dart';
import 'package:field_service/features/admin/domain/entities/managed_employee.dart';
import 'package:field_service/features/admin/domain/repositories/admin_repository.dart';

/// Data-layer implementation of [AdminRepository].
///
/// Deliberately a thin pass-through: authorization, validation, timestamps, the
/// audit log and the "never a hard delete" rule all live in the database
/// (`admin_management_setup.sql`). This class must not add policy of its own —
/// the server stays the single source of truth.
class AdminRepositoryImpl implements AdminRepository {
  const AdminRepositoryImpl(this._remoteDataSource);

  final AdminRemoteDataSource _remoteDataSource;

  @override
  Future<List<ManagedEmployee>> listEmployees() =>
      _remoteDataSource.listEmployees();

  @override
  Future<ManagedEmployee> setEmployeeStatus({
    required String employeeId,
    required AdminAccountStatus status,
  }) => _remoteDataSource.setEmployeeStatus(
    employeeId: employeeId,
    status: status,
  );

  @override
  Future<List<ManagedCustomer>> listCustomers({String? search}) =>
      _remoteDataSource.listCustomers(search: search);

  @override
  Future<ManagedCustomer> createCustomer({
    required String name,
    required String address,
    String? phone,
    String? email,
    String? city,
    String? postalCode,
    String? notes,
  }) => _remoteDataSource.createCustomer(
    name: name,
    address: address,
    phone: phone,
    email: email,
    city: city,
    postalCode: postalCode,
    notes: notes,
  );

  @override
  Future<ManagedCustomer> updateCustomer({
    required String customerId,
    required String name,
    required String address,
    String? phone,
    String? email,
    String? city,
    String? postalCode,
    String? notes,
  }) => _remoteDataSource.updateCustomer(
    customerId: customerId,
    name: name,
    address: address,
    phone: phone,
    email: email,
    city: city,
    postalCode: postalCode,
    notes: notes,
  );

  @override
  Future<ManagedCustomer> setCustomerStatus({
    required String customerId,
    required AdminAccountStatus status,
  }) => _remoteDataSource.setCustomerStatus(
    customerId: customerId,
    status: status,
  );

  @override
  Future<Set<String>> unavailableCustomerIds() =>
      _remoteDataSource.unavailableCustomerIds();
}
