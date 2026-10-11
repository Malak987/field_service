import 'package:equatable/equatable.dart';
import 'package:field_service/features/jobs/domain/entities/accessible_customer.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';

/// Which customer the form creates the job for.
enum TechnicianJobCustomerMode {
  /// Register a NEW customer (the form collects their details).
  newCustomer,

  /// Use an EXISTING customer the technician may already work for.
  existingCustomer,
}

/// Presentation state of the technician's "Create Customer & Job" form.
///
/// The customer's text fields stay in the form's controllers (they are
/// typed, not selected); everything the cubit owns is a *decision* or a
/// *server answer*: the mode, the chosen existing customer, the category,
/// the submission lifecycle and the created job.
class TechnicianJobFormState extends Equatable {
  const TechnicianJobFormState({
    this.mode = TechnicianJobCustomerMode.newCustomer,
    this.accessibleCustomers = const <AccessibleCustomer>[],
    this.isLoadingCustomers = false,
    this.customersFailed = false,
    this.selectedCustomerId,
    this.selectedCategory,
    this.isSubmitting = false,
    this.createdJob,
    this.queuedJobId,
    this.error,
    this.showValidationErrors = false,
  });

  /// New customer vs. existing customer.
  final TechnicianJobCustomerMode mode;

  /// The customers this technician may work for (server-scoped read — only
  /// customers already linked to one of their own jobs).
  final List<AccessibleCustomer> accessibleCustomers;

  /// The customer list is being loaded.
  final bool isLoadingCustomers;

  /// The customer list could not be loaded (offline, refused, …). The form
  /// stays usable in "new customer" mode.
  final bool customersFailed;

  /// The chosen existing customer (`customers.id`), or none yet.
  final String? selectedCustomerId;

  /// The chosen category — one of the two stable `JobCategory` values.
  final String? selectedCategory;

  /// A submission is in flight (the double-tap guard).
  final bool isSubmitting;

  /// The authoritative job row returned by the server after a successful
  /// creation (server job number, `assigned_at`, …).
  final Job? createdJob;

  /// The stable job id of a creation that is queued for a later sync —
  /// set instead of [createdJob] when the device was offline. The server has
  /// NOT confirmed it, so no job number exists yet.
  final String? queuedJobId;

  /// Submission error, when the server (or the network) refused.
  final Object? error;

  /// Whether missing-field hints should be shown (after a submit attempt).
  final bool showValidationErrors;

  bool get isNewCustomerMode => mode == TechnicianJobCustomerMode.newCustomer;

  bool get hasExistingCustomer => selectedCustomerId != null;

  bool get hasCategory => selectedCategory != null;

  /// The customer side of the form is complete for the current mode.
  bool get hasCustomer => isNewCustomerMode || hasExistingCustomer;

  bool get isComplete => hasCustomer && hasCategory;

  TechnicianJobFormState copyWith({
    TechnicianJobCustomerMode? mode,
    List<AccessibleCustomer>? accessibleCustomers,
    bool? isLoadingCustomers,
    bool? customersFailed,
    String? selectedCustomerId,
    bool clearSelectedCustomerId = false,
    String? selectedCategory,
    bool? isSubmitting,
    Job? createdJob,
    String? queuedJobId,
    Object? error,
    bool clearError = false,
    bool? showValidationErrors,
  }) {
    return TechnicianJobFormState(
      mode: mode ?? this.mode,
      accessibleCustomers: accessibleCustomers ?? this.accessibleCustomers,
      isLoadingCustomers: isLoadingCustomers ?? this.isLoadingCustomers,
      customersFailed: customersFailed ?? this.customersFailed,
      selectedCustomerId: clearSelectedCustomerId
          ? null
          : (selectedCustomerId ?? this.selectedCustomerId),
      selectedCategory: selectedCategory ?? this.selectedCategory,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      createdJob: createdJob ?? this.createdJob,
      queuedJobId: queuedJobId ?? this.queuedJobId,
      error: clearError ? null : (error ?? this.error),
      showValidationErrors: showValidationErrors ?? this.showValidationErrors,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    mode,
    accessibleCustomers,
    isLoadingCustomers,
    customersFailed,
    selectedCustomerId,
    selectedCategory,
    isSubmitting,
    createdJob,
    queuedJobId,
    error,
    showValidationErrors,
  ];
}
