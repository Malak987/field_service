import 'package:equatable/equatable.dart';

/// The customer information belonging to ONE specific job.
///
/// This is *not* a `Customer` entity from the Customers feature: technicians
/// must never hold (or cache) rows of the global `customers` table — that
/// table is admin-only in Supabase RLS. This value object carries exactly the
/// fields Job Details needs, fetched through the `get_job_customer(job_id)`
/// RPC, which only returns data when the job is assigned to the caller's
/// active employee (or the caller is an active admin).
class JobCustomerInfo extends Equatable {
  const JobCustomerInfo({
    required this.name,
    this.phone,
    this.address,
    this.city,
    this.postalCode,
  });

  /// `customers.name` of the job's customer.
  final String name;

  /// `customers.phone` (nullable).
  final String? phone;

  /// `customers.address` (nullable).
  final String? address;

  /// `customers.city` (nullable).
  final String? city;

  /// `customers.postal_code` (nullable).
  final String? postalCode;

  @override
  List<Object?> get props => <Object?>[name, phone, address, city, postalCode];
}
