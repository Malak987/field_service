import 'package:equatable/equatable.dart';

/// A customer the authenticated technician is entitled to work for.
///
/// Returned by the `technician_accessible_customers()` SECURITY DEFINER RPC,
/// whose scope is deliberately narrow: only customers already referenced by a
/// job assigned to the caller's own active employee row. `public.customers`
/// stays admin-only in RLS — this is not a general customer list and there is
/// no "customer by id" path for technicians.
///
/// Same layering as `JobCustomerInfo` (the per-job read of Job Details): a
/// small read-only projection owned by the Jobs feature, never access to the
/// Customers feature.
class AccessibleCustomer extends Equatable {
  const AccessibleCustomer({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    this.city,
    this.postalCode,
  });

  /// `customers.id` — the REAL customer identifier used to link a new job.
  final String id;

  /// `customers.name`.
  final String name;

  /// `customers.phone`.
  final String? phone;

  /// `customers.address`.
  final String? address;

  /// `customers.city`.
  final String? city;

  /// `customers.postal_code`.
  final String? postalCode;

  /// One-line contact detail for list rows (phone, else the address).
  String get subtitle {
    final String phone = (this.phone ?? '').trim();
    if (phone.isNotEmpty) {
      return phone;
    }
    return (address ?? '').trim();
  }

  @override
  List<Object?> get props => <Object?>[
    id,
    name,
    phone,
    address,
    city,
    postalCode,
  ];
}
