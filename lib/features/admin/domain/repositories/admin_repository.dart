import 'package:field_service/features/admin/domain/entities/admin_account_status.dart';
import 'package:field_service/features/admin/domain/entities/managed_customer.dart';
import 'package:field_service/features/admin/domain/entities/managed_employee.dart';

/// Domain contract of the admin management feature (technicians + customers).
///
/// Implementations must keep the *authorization* server-side: every operation
/// maps to an admin-only SECURITY DEFINER RPC of
/// `supabase/admin_management_setup.sql`, and each call is refused by the
/// database (SQLSTATE 42501) when the caller is not an active admin.
///
/// Failures are typed: implementations throw
/// [AdminFailure] (see `domain/entities/admin_failure.dart`) rather than
/// transport exceptions.
abstract interface class AdminRepository {
  /// Every employee row with its real name, its state and its job counters.
  Future<List<ManagedEmployee>> listEmployees();

  /// Blocks (`blocked`), unblocks (`active`) or soft deletes (`deleted`) one
  /// technician account. Never a hard delete; a soft deleted technician can
  /// never be reactivated here (enforced by the server).
  Future<ManagedEmployee> setEmployeeStatus({
    required String employeeId,
    required AdminAccountStatus status,
  });

  /// The customer management list, optionally filtered by [search].
  Future<List<ManagedCustomer>> listCustomers({String? search});

  /// Creates a customer (server validates name + address, stamps timestamps).
  Future<ManagedCustomer> createCustomer({
    required String name,
    required String address,
    String? phone,
    String? email,
    String? city,
    String? postalCode,
    String? notes,
  });

  /// Updates a customer's master data. Refused for soft deleted customers.
  Future<ManagedCustomer> updateCustomer({
    required String customerId,
    required String name,
    required String address,
    String? phone,
    String? email,
    String? city,
    String? postalCode,
    String? notes,
  });

  /// Blocks (`blocked`), unblocks (`active`) or soft deletes (`deleted`) one
  /// customer. Historical jobs, files and signatures are never touched.
  Future<ManagedCustomer> setCustomerStatus({
    required String customerId,
    required AdminAccountStatus status,
  });

  /// The ids of the customers that may NOT be used for a NEW job.
  Future<Set<String>> unavailableCustomerIds();
}
