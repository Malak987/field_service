import 'package:equatable/equatable.dart';
import 'package:field_service/features/customers/domain/entities/customer.dart';

/// Lifecycle of the customer list feed.
///
/// Note the deliberate absence of a "waiting for the network" meaning in
/// [CustomersStatus.loading]: the list always comes from Drift, so loading is
/// only "the first local snapshot has not been delivered yet" — milliseconds
/// on a device with data and, crucially, never blocked on internet access.
enum CustomersStatus { initial, loading, success, failure }

/// Presentation state for [CustomersCubit].
///
/// One contract serves both surfaces:
/// * the **list** page reads [customers],
/// * the **details** page reads [selectedCustomer].
class CustomersState extends Equatable {
  const CustomersState({
    this.status = CustomersStatus.initial,
    this.customers = const <Customer>[],
    this.selectedCustomer,
    this.error,
    this.isSaving = false,
    this.actionError,
    this.lastRefreshFailed = false,
  });

  /// Current lifecycle of the list feed.
  final CustomersStatus status;

  /// All local customers (list page), ordered by name.
  final List<Customer> customers;

  /// Single customer (details page); `null` while unresolved or deleted.
  final Customer? selectedCustomer;

  /// Last list-feed error, when [status] is [CustomersStatus.failure].
  final Object? error;

  /// A create/update/delete submission is in flight (drives button
  /// busy-states). Local writes only — never gated on connectivity.
  final bool isSaving;

  /// Failure of the last create/update/delete attempt (e.g.
  /// `CustomerLinkedToJobsException`). Pages show it once and clear it.
  final Object? actionError;

  /// The last remote refresh failed (network/RLS); the displayed data is
  /// still the valid local mirror. Drives the subtle "sync" warning only.
  final bool lastRefreshFailed;

  CustomersState copyWith({
    CustomersStatus? status,
    List<Customer>? customers,
    Customer? selectedCustomer,
    Object? error,
    bool? isSaving,
    Object? actionError,
    bool? lastRefreshFailed,
    bool clearError = false,
    bool clearSelectedCustomer = false,
    bool clearActionError = false,
  }) {
    return CustomersState(
      status: status ?? this.status,
      customers: customers ?? this.customers,
      selectedCustomer: clearSelectedCustomer
          ? null
          : (selectedCustomer ?? this.selectedCustomer),
      error: clearError ? null : (error ?? this.error),
      isSaving: isSaving ?? this.isSaving,
      actionError: clearActionError ? null : (actionError ?? this.actionError),
      lastRefreshFailed: lastRefreshFailed ?? this.lastRefreshFailed,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    customers,
    selectedCustomer,
    error,
    isSaving,
    actionError,
    lastRefreshFailed,
  ];
}
