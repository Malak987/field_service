import 'package:equatable/equatable.dart';

/// The customer a technician registers while creating a job.
///
/// Pure data — no id, no timestamps: the stable `customers.id` and every
/// timestamp are owned by the creation flow (the repository derives a stable
/// id from its idempotency key, the `technician_create_customer_and_job` RPC
/// stamps `created_at` / `updated_at` with `now()`).
///
/// Field set is exactly the real `public.customers` columns the app writes
/// (`name`, `phone`, `email`, `address`, `city`, `postal_code`, `notes`) —
/// no invented columns. [name] and [address] are the two NOT NULL columns.
class NewCustomerDraft extends Equatable {
  const NewCustomerDraft({
    required this.name,
    required this.address,
    this.phone,
    this.email,
    this.city,
    this.postalCode,
    this.notes,
  });

  /// `customers.name` (NOT NULL on the backend).
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

  /// `customers.notes` (free-form, e.g. site access instructions).
  final String? notes;

  /// The sync-payload shape (`snake_case`, JSON-serialisable).
  ///
  /// One owner of the payload schema: the enqueue side
  /// (`JobsRepositoryImpl`) and the replay side (`JobSyncHandler`) both go
  /// through this pair, so a queued operation can always be replayed exactly
  /// as it was created.
  Map<String, Object?> toPayload() => <String, Object?>{
    nameKey: name,
    addressKey: address,
    phoneKey: phone,
    emailKey: email,
    cityKey: city,
    postalCodeKey: postalCode,
    notesKey: notes,
  };

  /// Rebuilds a draft from a queued operation payload ([toPayload]).
  ///
  /// Throws [FormatException] on a malformed payload instead of inventing
  /// values: a corrupt queue row must surface as a failed sync, never as a
  /// half-written customer.
  factory NewCustomerDraft.fromPayload(Map<String, Object?> payload) {
    final Object? name = payload[nameKey];
    final Object? address = payload[addressKey];
    if (name is! String || address is! String) {
      throw const FormatException(
        'Customer draft payload is missing its name or address.',
      );
    }
    return NewCustomerDraft(
      name: name,
      address: address,
      phone: payload[phoneKey] as String?,
      email: payload[emailKey] as String?,
      city: payload[cityKey] as String?,
      postalCode: payload[postalCodeKey] as String?,
      notes: payload[notesKey] as String?,
    );
  }

  // Payload keys — declared here so the writer and the reader share them.
  static const String nameKey = 'name';
  static const String addressKey = 'address';
  static const String phoneKey = 'phone';
  static const String emailKey = 'email';
  static const String cityKey = 'city';
  static const String postalCodeKey = 'postal_code';
  static const String notesKey = 'notes';

  @override
  List<Object?> get props => <Object?>[
    name,
    address,
    phone,
    email,
    city,
    postalCode,
    notes,
  ];
}
