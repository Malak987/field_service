import 'package:equatable/equatable.dart';
import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/employees/domain/entities/employee.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';

/// Presentation state of the admin Create Job form.
///
/// One form, four facts: the customer, the category, the description and the
/// assigned technician. Options come from the EXISTING features — customers
/// from the offline-first Customers repository (Drift stream), technicians
/// from the Employees read — nothing is duplicated here.
class CreateJobState extends Equatable {
  const CreateJobState({
    this.customers = const <Customer>[],
    this.technicians = const <Employee>[],
    this.isLoadingCustomers = true,
    this.isLoadingTechnicians = true,
    this.customerOptionsFailed = false,
    this.technicianOptionsFailed = false,
    this.selectedCustomerId,
    this.selectedCategory,
    this.description = '',
    this.selectedTechnicianId,
    this.isSubmitting = false,
    this.createdJob,
    this.error,
    this.showValidationErrors = false,
  });

  /// Selectable customers (existing Customers feature, offline-first).
  final List<Customer> customers;

  /// Selectable ACTIVE technicians (never admins, never inactive).
  final List<Employee> technicians;

  /// Independent option loading keeps one completed source from masking another.
  final bool isLoadingCustomers;
  final bool isLoadingTechnicians;

  /// Customer and technician option load failures are distinct from empty lists.
  final bool customerOptionsFailed;
  final bool technicianOptionsFailed;

  /// The chosen customer (`customers.id`), or none yet.
  final String? selectedCustomerId;

  /// The chosen category — one of the two stable `JobCategory` values, or
  /// none yet. Never free text.
  final String? selectedCategory;

  /// The admin's initial job description (what the customer requested).
  /// NOT the technician's future Work Details.
  final String description;

  /// The chosen technician (`employees.id`), or none yet.
  final String? selectedTechnicianId;

  /// The Create & Assign request is in flight.
  final bool isSubmitting;

  /// The authoritative job row returned by the server after a successful
  /// Create & Assign (server job number, `assigned_at`, …).
  final Job? createdJob;

  /// Submission error, when the server (or the network) refused.
  final Object? error;

  /// Whether missing-field hints should be shown (after a submit attempt).
  final bool showValidationErrors;

  bool get hasCustomer => selectedCustomerId != null;
  bool get hasCategory => selectedCategory != null;
  bool get hasTechnician => selectedTechnicianId != null;
  bool get isComplete => hasCustomer && hasCategory && hasTechnician;

  CreateJobState copyWith({
    List<Customer>? customers,
    List<Employee>? technicians,
    bool? isLoadingCustomers,
    bool? isLoadingTechnicians,
    bool? customerOptionsFailed,
    bool? technicianOptionsFailed,
    String? selectedCustomerId,
    String? selectedCategory,
    String? description,
    String? selectedTechnicianId,
    bool? isSubmitting,
    Job? createdJob,
    Object? error,
    bool clearError = false,
    bool? showValidationErrors,
  }) {
    return CreateJobState(
      customers: customers ?? this.customers,
      technicians: technicians ?? this.technicians,
      isLoadingCustomers: isLoadingCustomers ?? this.isLoadingCustomers,
      isLoadingTechnicians: isLoadingTechnicians ?? this.isLoadingTechnicians,
      customerOptionsFailed: customerOptionsFailed ?? this.customerOptionsFailed,
      technicianOptionsFailed:
          technicianOptionsFailed ?? this.technicianOptionsFailed,
      selectedCustomerId: selectedCustomerId ?? this.selectedCustomerId,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      description: description ?? this.description,
      selectedTechnicianId: selectedTechnicianId ?? this.selectedTechnicianId,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      createdJob: createdJob ?? this.createdJob,
      error: clearError ? null : (error ?? this.error),
      showValidationErrors: showValidationErrors ?? this.showValidationErrors,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    customers,
    technicians,
    isLoadingCustomers,
    isLoadingTechnicians,
    customerOptionsFailed,
    technicianOptionsFailed,
    selectedCustomerId,
    selectedCategory,
    description,
    selectedTechnicianId,
    isSubmitting,
    createdJob,
    error,
    showValidationErrors,
  ];
}
