import 'package:field_service/features/admin/data/models/managed_customer_model.dart';
import 'package:field_service/features/admin/data/models/managed_employee_model.dart';
import 'package:field_service/features/admin/domain/entities/admin_account_status.dart';
import 'package:field_service/features/admin/domain/entities/admin_failure.dart';
import 'package:field_service/features/admin/domain/entities/managed_customer.dart';
import 'package:field_service/features/admin/domain/entities/managed_employee.dart';
import 'package:field_service/core/utils/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Remote access to the admin management RPCs of
/// `supabase/admin_management_setup.sql`.
///
/// Every statement issued here is a **SECURITY DEFINER function whose first
/// step is an inline "is the caller an active admin?" check** — the client
/// never decides who may manage what, and no table is ever written directly
/// from this screen:
///
/// * `admin_list_employees()`                     → technicians (+ job counters)
/// * `admin_set_employee_status(id, status)`      → block / unblock / soft delete
/// * `admin_list_customers(search)`               → customer management list
/// * `admin_create_customer(...)`                 → validated insert
/// * `admin_update_customer(...)`                 → master-data edit
/// * `admin_set_customer_status(id, status)`      → block / unblock / soft delete
/// * `admin_unavailable_customer_ids()`           → blocked/deleted customer ids
///
/// A technician calling any of these directly (the router refuses the pages,
/// but a modified client could still call them) is refused by the database
/// with SQLSTATE 42501, which this data source surfaces as
/// [AdminFailureKind.notAuthorized]. The same is true for `anon`.
abstract interface class AdminRemoteDataSource {
  /// All employees with their real names, their state and their job counters.
  Future<List<ManagedEmployee>> listEmployees();

  /// Applies a lifecycle transition to one technician account.
  Future<ManagedEmployee> setEmployeeStatus({
    required String employeeId,
    required AdminAccountStatus status,
  });

  /// The customer management list (optionally filtered server-side).
  Future<List<ManagedCustomer>> listCustomers({String? search});

  /// Creates a customer through the server (validated, server timestamps).
  Future<ManagedCustomer> createCustomer({
    required String name,
    required String address,
    String? phone,
    String? email,
    String? city,
    String? postalCode,
    String? notes,
  });

  /// Updates a customer's master data (never its status).
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

  /// Applies a lifecycle transition to one customer.
  Future<ManagedCustomer> setCustomerStatus({
    required String customerId,
    required AdminAccountStatus status,
  });

  /// Ids of the customers that may NOT be chosen for a new job (blocked or
  /// soft deleted). Used to filter the Create Job selector; the authoritative
  /// refusal happens inside `create_job` (`F0008`).
  Future<Set<String>> unavailableCustomerIds();
}

class AdminRemoteDataSourceImpl implements AdminRemoteDataSource {
  const AdminRemoteDataSourceImpl(this.supabase);

  final SupabaseClient supabase;

  @override
  Future<List<ManagedEmployee>> listEmployees() {
    return _guard(() async {
      final List<Map<String, dynamic>> rows = await _rpcRows(
        'admin_list_employees',
      );
      return rows.map(ManagedEmployeeModel.fromRow).toList();
    });
  }

  @override
  Future<ManagedEmployee> setEmployeeStatus({
    required String employeeId,
    required AdminAccountStatus status,
  }) {
    return _guard(() async {
      final List<Map<String, dynamic>> rows = await _rpcRows(
        'admin_set_employee_status',
        params: <String, dynamic>{
          'p_employee_id': employeeId,
          'p_status': status.remoteValue,
        },
      );
      if (rows.isEmpty) {
        throw const AdminFailure(
          AdminFailureKind.notFound,
          message: 'The employee row was not returned.',
        );
      }
      return ManagedEmployeeModel.fromRow(rows.first);
    });
  }

  @override
  Future<List<ManagedCustomer>> listCustomers({String? search}) {
    return _guard(() async {
      final List<Map<String, dynamic>> rows = await _rpcRows(
        'admin_list_customers',
        params: <String, dynamic>{'p_search': search},
      );
      return rows.map(ManagedCustomerModel.fromRow).toList();
    });
  }

  @override
  Future<ManagedCustomer> createCustomer({
    required String name,
    required String address,
    String? phone,
    String? email,
    String? city,
    String? postalCode,
    String? notes,
  }) {
    return _guard(() async {
      final List<Map<String, dynamic>> rows = await _rpcRows(
        'admin_create_customer',
        params: <String, dynamic>{
          'p_name': name,
          'p_address': address,
          'p_phone': phone,
          'p_email': email,
          'p_city': city,
          'p_postal_code': postalCode,
          'p_notes': notes,
        },
      );
      if (rows.isEmpty) {
        throw const AdminFailure(
          AdminFailureKind.notFound,
          message: 'The created customer row was not returned.',
        );
      }
      return ManagedCustomerModel.fromRow(rows.first);
    });
  }

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
  }) {
    return _guard(() async {
      final List<Map<String, dynamic>> rows = await _rpcRows(
        'admin_update_customer',
        params: <String, dynamic>{
          'p_customer_id': customerId,
          'p_name': name,
          'p_address': address,
          'p_phone': phone,
          'p_email': email,
          'p_city': city,
          'p_postal_code': postalCode,
          'p_notes': notes,
        },
      );
      if (rows.isEmpty) {
        throw const AdminFailure(
          AdminFailureKind.notFound,
          message: 'The updated customer row was not returned.',
        );
      }
      return ManagedCustomerModel.fromRow(rows.first);
    });
  }

  @override
  Future<ManagedCustomer> setCustomerStatus({
    required String customerId,
    required AdminAccountStatus status,
  }) {
    return _guard(() async {
      final List<Map<String, dynamic>> rows = await _rpcRows(
        'admin_set_customer_status',
        params: <String, dynamic>{
          'p_customer_id': customerId,
          'p_status': status.remoteValue,
        },
      );
      if (rows.isEmpty) {
        throw const AdminFailure(
          AdminFailureKind.notFound,
          message: 'The customer row was not returned.',
        );
      }
      return ManagedCustomerModel.fromRow(rows.first);
    });
  }

  @override
  Future<Set<String>> unavailableCustomerIds() {
    return _guard(() async {
      final dynamic response = await supabase.rpc(
        'admin_unavailable_customer_ids',
      );
      if (response == null) {
        return <String>{};
      }
      if (response is List) {
        return response
            .map((Object? id) => id?.toString() ?? '')
            .where((String id) => id.isNotEmpty)
            .toSet();
      }
      return <String>{};
    });
  }

  /// A `RETURNS TABLE (...)` RPC comes back as a list of row maps; a scalar
  /// response is normalised into the same list shape.
  Future<List<Map<String, dynamic>>> _rpcRows(
    String function, {
    Map<String, dynamic>? params,
  }) async {
    final dynamic response = await supabase.rpc(function, params: params);
    if (response == null) {
      return const <Map<String, dynamic>>[];
    }
    if (response is List) {
      return response
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> row) => Map<String, dynamic>.from(row))
          .toList();
    }
    if (response is Map) {
      return <Map<String, dynamic>>[Map<String, dynamic>.from(response)];
    }
    return const <Map<String, dynamic>>[];
  }

  /// Runs [action], translating every transport-level exception into one
  /// domain [AdminFailure] (so no Supabase type ever reaches a Cubit or a
  /// widget).
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AdminFailure {
      rethrow;
    } on PostgrestException catch (error, stackTrace) {
      final AdminFailure failure = _mapPostgrest(error);
      AppLogger.warning(
        'Admin management RPC refused/failed (${failure.kind.name}).',
        error: error,
        stackTrace: stackTrace,
      );
      throw failure;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Admin management RPC could not be reached.',
        error: error,
        stackTrace: stackTrace,
      );
      throw AdminFailure(
        _looksLikeNetworkError(error)
            ? AdminFailureKind.network
            : AdminFailureKind.unknown,
        message: error.toString(),
      );
    }
  }

  /// Maps the SQLSTATE (and, for `P0001`, the RAISE message) raised by the
  /// migration onto the typed presentation failure.
  AdminFailure _mapPostgrest(PostgrestException error) {
    final String code = error.code ?? '';
    final String message = error.message;
    final String lower = message.toLowerCase();

    switch (code) {
      case '42501':
        return AdminFailure(
          AdminFailureKind.notAuthorized,
          code: code,
          message: message,
        );
      case '28000':
        // Not authenticated / no active employee linked to the account —
        // from the UI's point of view the same as "not an admin".
        return AdminFailure(
          AdminFailureKind.notAuthorized,
          code: code,
          message: message,
        );
      case 'P0002':
        return AdminFailure(
          AdminFailureKind.notFound,
          code: code,
          message: message,
        );
      case 'F0008':
        return AdminFailure(
          AdminFailureKind.customerBlocked,
          code: code,
          message: message,
        );
      case 'P0001':
        if (lower.contains('deleted')) {
          return AdminFailure(
            AdminFailureKind.recordDeleted,
            code: code,
            message: message,
          );
        }
        return AdminFailure(
          AdminFailureKind.invalidInput,
          code: code,
          message: message,
        );
      default:
        if (lower.contains('deleted')) {
          return AdminFailure(
            AdminFailureKind.recordDeleted,
            code: code,
            message: message,
          );
        }
        if (lower.contains('admin')) {
          return AdminFailure(
            AdminFailureKind.notAuthorized,
            code: code,
            message: message,
          );
        }
        return AdminFailure(
          AdminFailureKind.unknown,
          code: code,
          message: message,
        );
    }
  }

  /// Offline requests surface as socket/HTTP client failures. The check stays
  /// string based on purpose: `dart:io` is unavailable on the web build.
  bool _looksLikeNetworkError(Object error) {
    final String text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('clientexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection refused') ||
        text.contains('connection closed') ||
        text.contains('timeout') ||
        text.contains('network is unreachable') ||
        text.contains('xmlhttprequest');
  }
}
