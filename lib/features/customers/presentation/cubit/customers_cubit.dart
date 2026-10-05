import 'dart:async';

import 'package:field_service/core/utils/logger.dart';
import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/customers/domain/repositories/customers_repository.dart';
import 'package:field_service/features/customers/domain/usecases/create_customer.dart';
import 'package:field_service/features/customers/domain/usecases/delete_customer.dart';
import 'package:field_service/features/customers/domain/usecases/get_customer_by_id.dart';
import 'package:field_service/features/customers/domain/usecases/get_customers.dart';
import 'package:field_service/features/customers/domain/usecases/refresh_customers.dart';
import 'package:field_service/features/customers/domain/usecases/update_customer.dart';
import 'package:field_service/features/customers/presentation/cubit/customers_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Outcome of a delete attempt (typed so the page can pick the right message
/// without inspecting exceptions).
enum CustomerDeleteOutcome {
  /// Deleted locally; the `delete` operation is queued and will be pushed.
  success,

  /// Refused: local jobs still reference this customer.
  linkedToJobs,

  /// Unexpected persistence failure (see the logged error).
  failure,
}

/// State holder for every Customers surface.
///
/// Offline-first contract: the data flows are **streams from Drift**, so
/// [loadCustomers] / [loadCustomer] paint with local data immediately even
/// with the internet switched off; the remote pull afterwards only improves
/// the mirror (and the streams re-emit on their own when it lands). All
/// data access goes through use cases — this layer never sees Supabase or
/// Drift types.
///
/// Registered as a **factory** in DI: the list page, the details page and
/// each form page own an instance, matching the `JobsCubit` convention.
class CustomersCubit extends Cubit<CustomersState> {
  CustomersCubit({
    required this._getCustomers,
    required this._getCustomerById,
    required this._createCustomer,
    required this._updateCustomer,
    required this._deleteCustomer,
    required this._refreshCustomers,
  }) : super(const CustomersState());

  final GetCustomers _getCustomers;
  final GetCustomerById _getCustomerById;
  final CreateCustomer _createCustomer;
  final UpdateCustomer _updateCustomer;
  final DeleteCustomer _deleteCustomer;
  final RefreshCustomers _refreshCustomers;

  StreamSubscription<List<Customer>>? _listSubscription;
  StreamSubscription<Customer?>? _detailSubscription;

  @override
  Future<void> close() async {
    await _listSubscription?.cancel();
    await _detailSubscription?.cancel();
    return super.close();
  }

  // --- Reads (local first, then background pull) ---------------------------------

  /// Opens the live local customer list, then synchronizes with the backend.
  Future<void> loadCustomers() async {
    emit(state.copyWith(status: CustomersStatus.loading, clearError: true));

    await _listSubscription?.cancel();
    _listSubscription = _getCustomers().listen(
      (List<Customer> customers) {
        if (isClosed) {
          return;
        }
        emit(
          state.copyWith(status: CustomersStatus.success, customers: customers),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        if (isClosed) {
          return;
        }
        AppLogger.warning(
          'Customer list stream failed.',
          error: error,
          stackTrace: stackTrace,
        );
        emit(state.copyWith(status: CustomersStatus.failure, error: error));
      },
    );

    await _refreshRemote();
  }

  /// Opens one customer as a live local stream (details page).
  Future<void> loadCustomer(String id) async {
    emit(
      state.copyWith(
        status: CustomersStatus.loading,
        clearError: true,
        clearSelectedCustomer: true,
      ),
    );

    await _detailSubscription?.cancel();
    _detailSubscription = _getCustomerById(id).listen(
      (Customer? customer) {
        if (isClosed) {
          return;
        }
        emit(
          state.copyWith(
            status: CustomersStatus.success,
            selectedCustomer: customer,
            clearSelectedCustomer: customer == null,
          ),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        if (isClosed) {
          return;
        }
        AppLogger.warning(
          'Customer detail stream failed.',
          error: error,
          stackTrace: stackTrace,
        );
        emit(state.copyWith(status: CustomersStatus.failure, error: error));
      },
    );

    await _refreshRemote();
  }

  /// Pull-to-refresh: refetch remote rows into Drift. The visible list is
  /// never cleared or gated — a failed pull only flags [lastRefreshFailed]
  /// so the sync badge can explain itself.
  Future<void> refresh() => _refreshRemote();

  // --- Writes (local + queued, never network-blocking) -----------------------------

  /// Creates a customer offline-first. Returns `true` on success; on failure
  /// [CustomersState.actionError] carries the reason for the page to show.
  Future<bool> createCustomer({
    required String name,
    required String address,
    String? phone,
    String? email,
    String? city,
    String? postalCode,
    String? notes,
  }) async {
    emit(state.copyWith(isSaving: true, clearActionError: true));

    try {
      await _createCustomer(
        name: name,
        address: address,
        phone: phone,
        email: email,
        city: city,
        postalCode: postalCode,
        notes: notes,
      );
      if (!isClosed) {
        emit(state.copyWith(isSaving: false));
      }
      await _refreshRemote();
      return true;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to create customer.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!isClosed) {
        emit(state.copyWith(isSaving: false, actionError: error));
      }
      return false;
    }
  }

  /// Updates an existing customer. Same contract as [createCustomer].
  Future<bool> updateCustomer(Customer customer) async {
    emit(state.copyWith(isSaving: true, clearActionError: true));

    try {
      await _updateCustomer(customer);
      if (!isClosed) {
        emit(state.copyWith(isSaving: false));
      }
      await _refreshRemote();
      return true;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to update customer.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!isClosed) {
        emit(state.copyWith(isSaving: false, actionError: error));
      }
      return false;
    }
  }

  /// Deletes a customer. A [CustomerLinkedToJobsException] from the
  /// repository becomes [CustomerDeleteOutcome.linkedToJobs] — the customer
  /// is kept untouched in that case, locally and remotely.
  Future<CustomerDeleteOutcome> deleteCustomer(String id) async {
    emit(state.copyWith(isSaving: true, clearActionError: true));

    try {
      await _deleteCustomer(id);
      if (!isClosed) {
        emit(state.copyWith(isSaving: false));
      }
      await _refreshRemote();
      return CustomerDeleteOutcome.success;
    } on CustomerLinkedToJobsException {
      if (!isClosed) {
        emit(state.copyWith(isSaving: false));
      }
      return CustomerDeleteOutcome.linkedToJobs;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to delete customer.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!isClosed) {
        emit(state.copyWith(isSaving: false, actionError: error));
      }
      return CustomerDeleteOutcome.failure;
    }
  }

  // --- Internals ---------------------------------------------------------------------

  Future<void> _refreshRemote() async {
    try {
      await _refreshCustomers();
      if (!isClosed) {
        emit(state.copyWith(lastRefreshFailed: false));
      }
    } catch (error, stackTrace) {
      // The local mirror remains the displayed truth; the badge reflects the
      // failed attempt. No error state for the list, ever.
      AppLogger.warning(
        'Customer refresh from backend failed; local data stays visible.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!isClosed) {
        emit(state.copyWith(lastRefreshFailed: true));
      }
    }
  }
}
