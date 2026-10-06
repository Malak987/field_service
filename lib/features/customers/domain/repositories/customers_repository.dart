import 'package:field_service/features/customers/domain/entities/customer.dart';

/// Domain contract for accessing customer data — **offline-first**.
///
/// Read paths never touch the network: they serve the local Drift mirror,
/// which is the source of truth for the UI. Write paths commit locally and
/// enqueue a `SyncOperation` (create/update/delete) for the sync engine;
/// Supabase is reached only by the engine (push) and by [refreshFromRemote]
/// (pull). `public.customers` is **admin-only** in Supabase RLS — this
/// contract is only ever exercised for admin sessions (enforced in-app by
/// the router guard); technicians will later see per-job customer info
/// through their assigned jobs, never through this global contract.
abstract interface class CustomersRepository {
  /// The complete local customer list, ordered by name.
  ///
  /// Emits immediately with the current Drift state and again after every
  /// local write or merged pull — so "read Drift → display" works with the
  /// radio switched off, and "sync later → refresh UI" comes for free.
  Stream<List<Customer>> watchCustomers();

  /// One local customer as a live stream (`null` when it no longer exists).
  Stream<Customer?> watchCustomerById(String id);

  /// One local customer, once (`null` when unknown).
  Future<Customer?> getCustomerById(String id);

  /// Creates a customer offline-first:
  /// 1. assigns a stable client-generated UUID,
  /// 2. stores the row in Drift marked `pending`,
  /// 3. enqueues a `create` [SyncOperation].
  ///
  /// The returned [Customer] is the saved row, ready to render immediately.
  Future<Customer> createCustomer({
    required String name,
    required String address,
    String? phone,
    String? email,
    String? city,
    String? postalCode,
    String? notes,
  });

  /// Updates a customer locally (stays `pending`) and enqueues an `update`
  /// [SyncOperation]. The id is never changed — jobs reference it.
  Future<void> updateCustomer(Customer customer);

  /// Deletes a customer locally and enqueues a `delete` [SyncOperation].
  ///
  /// Throws [CustomerLinkedToJobsException] when local jobs still reference
  /// the customer (the remote `jobs.customer_id` FK is the final backstop:
  /// a rejected push stays failed and retryable, never destructive).
  Future<void> deleteCustomer(String id);

  /// Pulls the visible remote customers and merges them into Drift.
  ///
  /// Rows with unfinished queue operations are protected and skipped, so a
  /// pull can never clobber (or resurrect-clobber) local pending work.
  /// Throws when the backend is unreachable; callers decide whether that is
  /// an error or just "still offline".
  Future<void> refreshFromRemote();

  /// Number of locally-known jobs referencing the customer with [id]
  /// (delete guard; the server-side constraint remains authoritative).
  Future<int> countLinkedJobs(String id);
}

/// Raised by [CustomersRepository.deleteCustomer] when local jobs still
/// reference the customer, so the UI can explain rather than silently
/// "succeeding" a delete that the backend FK would reject.
class CustomerLinkedToJobsException implements Exception {
  const CustomerLinkedToJobsException(this.customerId, this.linkedJobs);

  final String customerId;
  final int linkedJobs;

  @override
  String toString() =>
      'CustomerLinkedToJobsException($customerId, $linkedJobs linked jobs)';
}
