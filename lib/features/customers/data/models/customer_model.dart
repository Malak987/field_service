import 'package:drift/drift.dart';
import 'package:field_service/core/database/app_database.dart';
import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/customers/domain/entities/customer_sync_status.dart';

/// Data-layer mapping for a customer row.
///
/// Translates between the three shapes a customer exists in:
/// * a **Supabase row map** (snake_case columns, ISO timestamps) —
///   [fromRemoteRow], [toRemoteRow], [toRemoteUpdate],
/// * a **Drift row** ([LocalCustomer]) — [fromLocalRow], [toLocalCompanion],
/// * the domain [Customer] it extends.
///
/// Keeping every conversion here means the data sources stay mechanical and
/// the sync payload format has exactly one owner.
class CustomerModel extends Customer {
  const CustomerModel({
    required super.id,
    required super.name,
    required super.address,
    required super.createdAt,
    required super.updatedAt,
    required super.syncStatus,
    super.phone,
    super.email,
    super.city,
    super.postalCode,
    super.notes,
  });

  /// Maps a raw Supabase/PostgREST row.
  ///
  /// A row that just came from the backend is by definition in sync —
  /// [CustomerSyncStatus.synced] is set unconditionally.
  factory CustomerModel.fromRemoteRow(Map<String, Object?> row) {
    return CustomerModel(
      id: row['id']! as String,
      name: row['name']! as String,
      phone: row['phone'] as String?,
      email: row['email'] as String?,
      address: row['address']! as String,
      city: row['city'] as String?,
      postalCode: row['postal_code'] as String?,
      notes: row['notes'] as String?,
      createdAt: _parseTimestamp(row['created_at']),
      updatedAt: _parseTimestamp(row['updated_at']),
      syncStatus: CustomerSyncStatus.synced,
    );
  }

  /// Maps a Drift row (local mirror + local sync metadata).
  factory CustomerModel.fromLocalRow(LocalCustomer row) {
    return CustomerModel(
      id: row.id,
      name: row.name,
      phone: row.phone,
      email: row.email,
      address: row.address,
      city: row.city,
      postalCode: row.postalCode,
      notes: row.notes,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      syncStatus: CustomerSyncStatus.values.byName(row.syncStatus),
    );
  }

  /// The full remote shape, used as the **create** payload and for upserts.
  ///
  /// `created_at` / `updated_at` are included so a record created offline is
  /// stored on the server with the moment it actually happened, not the
  /// moment the queue happened to drain.
  Map<String, Object?> toRemoteRow() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'city': city,
      'postal_code': postalCode,
      'notes': notes,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  /// The update payload: every mutable column except `id` (the row
  /// selector) and `created_at` (server-side, immutable).
  Map<String, Object?> toRemoteUpdate() {
    return <String, Object?>{
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'city': city,
      'postal_code': postalCode,
      'notes': notes,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  /// The Drift companion used for local inserts.
  CustomersTableCompanion toLocalCompanion({required bool isNew}) {
    return CustomersTableCompanion(
      id: Value(id),
      name: Value(name),
      phone: Value(phone),
      email: Value(email),
      address: Value(address),
      city: Value(city),
      postalCode: Value(postalCode),
      notes: Value(notes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      syncStatus: Value(syncStatus.name),
      localUpdatedAt: isNew ? Value(updatedAt) : const Value.absent(),
      lastSyncedAt: syncStatus == CustomerSyncStatus.synced
          ? Value(updatedAt)
          : const Value.absent(),
    );
  }

  CustomerModel copyWithSyncStatus(CustomerSyncStatus status) {
    return CustomerModel(
      id: id,
      name: name,
      phone: phone,
      email: email,
      address: address,
      city: city,
      postalCode: postalCode,
      notes: notes,
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncStatus: status,
    );
  }

  /// PostgREST returns timestamps as ISO-8601 strings; tests/fakes may
  /// provide real [DateTime]s. Anything else is a programming error and must
  /// surface, not silently corrupt a row.
  static DateTime _parseTimestamp(Object? value) {
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.parse(value);
    }
    throw FormatException('Unexpected timestamp value: $value');
  }
}
