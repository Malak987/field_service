import 'package:equatable/equatable.dart';
import 'package:field_service/core/utils/logger.dart';
import 'package:field_service/features/admin/domain/entities/admin_account_status.dart';
import 'package:field_service/features/admin/domain/entities/admin_failure.dart';
import 'package:field_service/features/admin/domain/entities/managed_customer.dart';
import 'package:field_service/features/admin/domain/usecases/create_managed_customer.dart';
import 'package:field_service/features/admin/domain/usecases/list_managed_customers.dart';
import 'package:field_service/features/admin/domain/usecases/set_customer_status.dart';
import 'package:field_service/features/admin/domain/usecases/update_managed_customer.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Loading state of the customer management list.
enum AdminCustomersStatus { initial, loading, success, failure }

/// State of the `إدارة العملاء / Manage Customers` screens (list, details and
/// the create/edit form share this cubit).
class AdminCustomersState extends Equatable {
  const AdminCustomersState({
    this.status = AdminCustomersStatus.initial,
    this.customers = const <ManagedCustomer>[],
    this.selectedCustomer,
    this.isBusy = false,
    this.busyCustomerId,
    this.isCustomerLoading = false,
    this.loadFailure,
  });

  final AdminCustomersStatus status;

  /// Every customer row the server returned (active, blocked and soft deleted —
  /// the management screen shows all of them, with their state).
  final List<ManagedCustomer> customers;

  /// The row a details/form page currently works on.
  final ManagedCustomer? selectedCustomer;

  /// A management action (status change / save) is in flight.
  final bool isBusy;

  /// Customer whose action is in flight.
  final String? busyCustomerId;

  /// A single customer is being resolved for the details/form pages.
  final bool isCustomerLoading;

  /// Why the LIST could not be loaded.
  final AdminFailureKind? loadFailure;

  bool get hasCustomers => customers.isNotEmpty;

  AdminCustomersState copyWith({
    AdminCustomersStatus? status,
    List<ManagedCustomer>? customers,
    ManagedCustomer? selectedCustomer,
    bool clearSelectedCustomer = false,
    bool? isBusy,
    String? busyCustomerId,
    bool clearBusyCustomerId = false,
    bool? isCustomerLoading,
    AdminFailureKind? loadFailure,
    bool clearLoadFailure = false,
  }) {
    return AdminCustomersState(
      status: status ?? this.status,
      customers: customers ?? this.customers,
      selectedCustomer: clearSelectedCustomer
          ? null
          : (selectedCustomer ?? this.selectedCustomer),
      isBusy: isBusy ?? this.isBusy,
      busyCustomerId: clearBusyCustomerId
          ? null
          : (busyCustomerId ?? this.busyCustomerId),
      isCustomerLoading: isCustomerLoading ?? this.isCustomerLoading,
      loadFailure: clearLoadFailure ? null : (loadFailure ?? this.loadFailure),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    customers,
    selectedCustomer,
    isBusy,
    busyCustomerId,
    isCustomerLoading,
    loadFailure,
  ];
}

/// State holder of the customer management screens.
///
/// Like the technician cubit, all authorization and all data rules live in the
/// database RPCs (`admin_list_customers`, `admin_create_customer`,
/// `admin_update_customer`, `admin_set_customer_status`); this cubit only
/// orchestrates the screen and reports typed failures.
class AdminCustomersCubit extends Cubit<AdminCustomersState> {
  AdminCustomersCubit({
    required ListManagedCustomers listManagedCustomers,
    required CreateManagedCustomer createManagedCustomer,
    required UpdateManagedCustomer updateManagedCustomer,
    required SetCustomerStatus setCustomerStatus,
  }) : _listManagedCustomers = listManagedCustomers,
       _createManagedCustomer = createManagedCustomer,
       _updateManagedCustomer = updateManagedCustomer,
       _setCustomerStatus = setCustomerStatus,
       super(const AdminCustomersState());

  final ListManagedCustomers _listManagedCustomers;
  final CreateManagedCustomer _createManagedCustomer;
  final UpdateManagedCustomer _updateManagedCustomer;
  final SetCustomerStatus _setCustomerStatus;

  /// Loads (or reloads) the management list.
  Future<void> load() async {
    emit(
      state.copyWith(
        status: AdminCustomersStatus.loading,
        clearLoadFailure: true,
      ),
    );

    try {
      final List<ManagedCustomer> customers = await _listManagedCustomers();
      if (isClosed) {
        return;
      }
      emit(
        AdminCustomersState(
          status: AdminCustomersStatus.success,
          customers: customers,
          selectedCustomer: state.selectedCustomer == null
              ? null
              : _findIn(customers, state.selectedCustomer!.id),
        ),
      );
    } on AdminFailure catch (failure, stackTrace) {
      _log('The customer list could not be loaded.', failure, stackTrace);
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          status: AdminCustomersStatus.failure,
          loadFailure: failure.kind,
        ),
      );
    } catch (error, stackTrace) {
      _log('The customer list could not be loaded.', error, stackTrace);
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          status: AdminCustomersStatus.failure,
          loadFailure: AdminFailureKind.unknown,
        ),
      );
    }
  }

  /// Resolves one customer for the details / edit pages.
  ///
  /// The management API exposes a list (there is no "get customer by id" RPC on
  /// purpose: a customer id alone is never a read grant), so the row is taken
  /// from the freshly loaded list.
  Future<AdminFailureKind?> loadCustomer(String customerId) async {
    emit(
      state.copyWith(
        isCustomerLoading: true,
        clearSelectedCustomer: true,
        clearLoadFailure: true,
      ),
    );

    try {
      final List<ManagedCustomer> customers = await _listManagedCustomers();
      final ManagedCustomer? customer = _findIn(customers, customerId);
      if (isClosed) {
        return null;
      }
      if (customer == null) {
        emit(
          state.copyWith(
            status: AdminCustomersStatus.success,
            customers: customers,
            isCustomerLoading: false,
            loadFailure: AdminFailureKind.notFound,
          ),
        );
        return AdminFailureKind.notFound;
      }
      emit(
        state.copyWith(
          status: AdminCustomersStatus.success,
          customers: customers,
          selectedCustomer: customer,
          isCustomerLoading: false,
          clearLoadFailure: true,
        ),
      );
      return null;
    } on AdminFailure catch (failure, stackTrace) {
      _log('The customer could not be loaded.', failure, stackTrace);
      if (!isClosed) {
        emit(
          state.copyWith(
            isCustomerLoading: false,
            loadFailure: failure.kind,
          ),
        );
      }
      return failure.kind;
    } catch (error, stackTrace) {
      _log('The customer could not be loaded.', error, stackTrace);
      if (!isClosed) {
        emit(
          state.copyWith(
            isCustomerLoading: false,
            loadFailure: AdminFailureKind.unknown,
          ),
        );
      }
      return AdminFailureKind.unknown;
    }
  }

  /// Blocks the customer: no NEW job can reference it any more; every existing
  /// job (and its files and signature) stays readable.
  Future<AdminFailureKind?> block(ManagedCustomer customer) =>
      _applyStatus(customer, AdminAccountStatus.blocked);

  /// Unblocks a blocked customer.
  Future<AdminFailureKind?> unblock(ManagedCustomer customer) =>
      _applyStatus(customer, AdminAccountStatus.active);

  /// SOFT deletes the customer — never a hard delete, never a cascade.
  Future<AdminFailureKind?> softDelete(ManagedCustomer customer) =>
      _applyStatus(customer, AdminAccountStatus.deleted);

  /// Creates a customer through the server. Returns `null` on success.
  Future<AdminFailureKind?> createCustomer({
    required String name,
    required String address,
    String? phone,
    String? email,
    String? city,
    String? postalCode,
    String? notes,
  }) async {
    if (state.isBusy) {
      return null;
    }

    emit(state.copyWith(isBusy: true));

    try {
      final ManagedCustomer created = await _createManagedCustomer(
        name: name,
        address: address,
        phone: phone,
        email: email,
        city: city,
        postalCode: postalCode,
        notes: notes,
      );
      if (isClosed) {
        return null;
      }
      emit(
        state.copyWith(
          status: AdminCustomersStatus.success,
          customers: _replace(state.customers, created),
          selectedCustomer: created,
          isBusy: false,
          clearLoadFailure: true,
        ),
      );
      return null;
    } on AdminFailure catch (failure, stackTrace) {
      _log('Creating the customer was refused.', failure, stackTrace);
      if (!isClosed) {
        emit(state.copyWith(isBusy: false));
      }
      return failure.kind;
    } catch (error, stackTrace) {
      _log('Creating the customer failed.', error, stackTrace);
      if (!isClosed) {
        emit(state.copyWith(isBusy: false));
      }
      return AdminFailureKind.unknown;
    }
  }

  /// Edits a customer's master data (never its status). Returns `null` on
  /// success.
  Future<AdminFailureKind?> updateCustomer({
    required String customerId,
    required String name,
    required String address,
    String? phone,
    String? email,
    String? city,
    String? postalCode,
    String? notes,
  }) async {
    if (state.isBusy) {
      return null;
    }

    emit(state.copyWith(isBusy: true, busyCustomerId: customerId));

    try {
      final ManagedCustomer updated = await _updateManagedCustomer(
        customerId: customerId,
        name: name,
        address: address,
        phone: phone,
        email: email,
        city: city,
        postalCode: postalCode,
        notes: notes,
      );
      if (isClosed) {
        return null;
      }
      emit(
        state.copyWith(
          status: AdminCustomersStatus.success,
          customers: _replace(state.customers, updated),
          selectedCustomer: updated,
          isBusy: false,
          clearBusyCustomerId: true,
          clearLoadFailure: true,
        ),
      );
      return null;
    } on AdminFailure catch (failure, stackTrace) {
      _log('Editing the customer was refused.', failure, stackTrace);
      if (!isClosed) {
        emit(state.copyWith(isBusy: false, clearBusyCustomerId: true));
      }
      return failure.kind;
    } catch (error, stackTrace) {
      _log('Editing the customer failed.', error, stackTrace);
      if (!isClosed) {
        emit(state.copyWith(isBusy: false, clearBusyCustomerId: true));
      }
      return AdminFailureKind.unknown;
    }
  }

  Future<AdminFailureKind?> _applyStatus(
    ManagedCustomer customer,
    AdminAccountStatus status,
  ) async {
    if (state.isBusy) {
      return null;
    }

    emit(state.copyWith(isBusy: true, busyCustomerId: customer.id));

    try {
      final ManagedCustomer updated = await _setCustomerStatus(
        customerId: customer.id,
        status: status,
      );
      if (isClosed) {
        return null;
      }
      emit(
        state.copyWith(
          status: AdminCustomersStatus.success,
          customers: _replace(state.customers, updated),
          selectedCustomer: updated,
          isBusy: false,
          clearBusyCustomerId: true,
          clearLoadFailure: true,
        ),
      );
      return null;
    } on AdminFailure catch (failure, stackTrace) {
      _log(
        'Changing the status of "${customer.name}" was refused.',
        failure,
        stackTrace,
      );
      if (!isClosed) {
        emit(state.copyWith(isBusy: false, clearBusyCustomerId: true));
      }
      return failure.kind;
    } catch (error, stackTrace) {
      _log('Changing the status of "${customer.name}" failed.', error, stackTrace);
      if (!isClosed) {
        emit(state.copyWith(isBusy: false, clearBusyCustomerId: true));
      }
      return AdminFailureKind.unknown;
    }
  }

  ManagedCustomer? _findIn(List<ManagedCustomer> customers, String id) {
    for (final ManagedCustomer customer in customers) {
      if (customer.id == id) {
        return customer;
      }
    }
    return null;
  }

  List<ManagedCustomer> _replace(
    List<ManagedCustomer> customers,
    ManagedCustomer updated,
  ) {
    final List<ManagedCustomer> next = <ManagedCustomer>[
      for (final ManagedCustomer customer in customers)
        if (customer.id == updated.id) updated else customer,
    ];
    if (!customers.any((ManagedCustomer c) => c.id == updated.id)) {
      next.add(updated);
    }
    return next;
  }

  void _log(String message, Object error, StackTrace stackTrace) {
    AppLogger.warning(message, error: error, stackTrace: stackTrace);
  }
}
