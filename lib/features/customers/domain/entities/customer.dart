import 'package:equatable/equatable.dart';
import 'package:field_service/features/customers/domain/entities/customer_sync_status.dart';

/// Domain entity representing a row in `public.customers`.
///
/// Fields map 1:1 to the real Supabase schema (no invented columns):
///
/// | Entity field     | Column                        |
/// |------------------|-------------------------------|
/// | [id]             | `id` (uuid, `gen_random_uuid()` default) |
/// | [name]           | `name` (text, NOT NULL)       |
/// | [phone]          | `phone` (text, nullable)      |
/// | [email]          | `email` (text, nullable)      |
/// | [address]        | `address` (text, NOT NULL)    |
/// | [city]           | `city` (text, nullable)       |
/// | [postalCode]     | `postal_code` (text, nullable)|
/// | [notes]          | `notes` (text, nullable)      |
/// | [createdAt]      | `created_at` (timestamptz)    |
/// | [updatedAt]      | `updated_at` (timestamptz)    |
///
/// [syncStatus] is the only local-only addition: the offline-first UI reads
/// Drift as its source of truth, so it must also show *how current* each row
/// is. The value never leaves the device.
///
/// The `id` is a **client-generated stable UUID** for records created
/// offline. `jobs.customer_id` references this id, so it must never be
/// replaced during synchronization — retries reuse it, which is what makes
/// pushes idempotent and prevents duplicate customers.
class Customer extends Equatable {
  const Customer({
    required this.id,
    required this.name,
    required this.address,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
    this.phone,
    this.email,
    this.city,
    this.postalCode,
    this.notes,
  });

  /// `customers.id` (uuid). Client generated for offline-first creation;
  /// stable for the entire lifetime of the record.
  final String id;

  /// `customers.name`.
  final String name;

  /// `customers.address` (the site address; NOT NULL on the backend).
  final String address;

  /// `customers.phone`.
  final String? phone;

  /// `customers.email`.
  final String? email;

  /// `customers.city`.
  final String? city;

  /// `customers.postal_code`.
  final String? postalCode;

  /// `customers.notes` (free-form, e.g. site instructions).
  final String? notes;

  /// `customers.created_at`.
  final DateTime createdAt;

  /// `customers.updated_at`.
  final DateTime updatedAt;

  /// Local-only synchronization state of this row.
  final CustomerSyncStatus syncStatus;

  /// Whether this customer may currently be pushed/edited locally
  /// (read-only while a change is in flight is *not* enforced here; RLS
  /// remains the security boundary — this flag only labels admin state).
  bool get hasUnsyncedChanges => syncStatus != CustomerSyncStatus.synced;

  /// "City, postal code" in one line for list rows and address blocks.
  String get cityLine {
    final List<String> parts = <String>[
      if ((city ?? '').trim().isNotEmpty) city!.trim(),
      if ((postalCode ?? '').trim().isNotEmpty) postalCode!.trim(),
    ];
    return parts.join(', ');
  }

  Customer copyWith({
    String? name,
    String? address,
    String? phone,
    String? email,
    String? city,
    String? postalCode,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    CustomerSyncStatus? syncStatus,
  }) {
    return Customer(
      id: id,
      name: name ?? this.name,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      city: city ?? this.city,
      postalCode: postalCode ?? this.postalCode,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
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
    createdAt,
    updatedAt,
    syncStatus,
  ];
}
