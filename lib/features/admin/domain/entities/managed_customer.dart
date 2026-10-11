import 'package:equatable/equatable.dart';
import 'package:field_service/features/admin/domain/entities/admin_account_status.dart';

/// One customer row as the admin management screen sees it.
///
/// Produced by the `admin_list_customers()` / `admin_create_customer()` /
/// `admin_update_customer()` / `admin_set_customer_status()` RPCs
/// (admin-only, enforced server-side). It mirrors the real `public.customers`
/// columns — no invented fields.
class ManagedCustomer extends Equatable {
  const ManagedCustomer({
    required this.id,
    required this.name,
    required this.address,
    this.phone,
    this.email,
    this.city,
    this.postalCode,
    this.notes,
    this.status = AdminAccountStatus.active,
    this.blockedAt,
    this.deletedAt,
    this.createdAt,
    this.updatedAt,
    this.jobsCount = 0,
  });

  /// `customers.id` (uuid).
  final String id;

  /// `customers.name`.
  final String name;

  /// `customers.address` (NOT NULL on the backend).
  final String address;

  /// `customers.phone`.
  final String? phone;

  /// `customers.email`.
  final String? email;

  /// `customers.city`.
  final String? city;

  /// `customers.postal_code`.
  final String? postalCode;

  /// `customers.notes`.
  final String? notes;

  /// Lifecycle state (`account_status`).
  final AdminAccountStatus status;

  /// When the customer was blocked (server timestamp).
  final DateTime? blockedAt;

  /// When the customer was soft deleted (server timestamp).
  final DateTime? deletedAt;

  /// `customers.created_at`.
  final DateTime? createdAt;

  /// `customers.updated_at`.
  final DateTime? updatedAt;

  /// How many jobs reference this customer (history included).
  final int jobsCount;

  bool get isDeleted => status.isDeleted;
  bool get isBlocked => status.isBlocked;
  bool get isActive => status.isActive;

  /// Only an ACTIVE customer may be chosen for a NEW job. The database
  /// enforces this anyway (`create_job` refuses blocked/deleted customers with
  /// `F0008`); the UI uses this flag to keep them out of the selector.
  bool get isSelectable => status.isActive;

  /// Editing is refused for a soft deleted customer (server-enforced).
  bool get canBeEdited => !isDeleted;

  /// Blocking is offered for a non-deleted, currently active customer.
  bool get canBeBlocked => !isDeleted && !isBlocked;

  /// Unblocking is offered for a blocked customer.
  bool get canBeUnblocked => !isDeleted && isBlocked;

  /// Soft delete is offered while the customer is not deleted yet.
  bool get canBeDeleted => !isDeleted;

  /// "City, postal code" in one line for list rows and address blocks
  /// (same shape as the Customers feature's [Customer.cityLine]).
  String get cityLine {
    final List<String> parts = <String>[
      if ((city ?? '').trim().isNotEmpty) city!.trim(),
      if ((postalCode ?? '').trim().isNotEmpty) postalCode!.trim(),
    ];
    return parts.join(', ');
  }

  ManagedCustomer copyWith({
    String? name,
    String? address,
    String? phone,
    String? email,
    String? city,
    String? postalCode,
    String? notes,
    AdminAccountStatus? status,
    DateTime? blockedAt,
    DateTime? deletedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? jobsCount,
  }) {
    return ManagedCustomer(
      id: id,
      name: name ?? this.name,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      city: city ?? this.city,
      postalCode: postalCode ?? this.postalCode,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      blockedAt: blockedAt ?? this.blockedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      jobsCount: jobsCount ?? this.jobsCount,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    id,
    name,
    address,
    phone,
    email,
    city,
    postalCode,
    notes,
    status,
    blockedAt,
    deletedAt,
    createdAt,
    updatedAt,
    jobsCount,
  ];
}
