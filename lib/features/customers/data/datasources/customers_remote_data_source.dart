import 'package:field_service/features/customers/data/models/customer_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Remote data source contract for the `public.customers` table.
///
/// Deliberately row-map based rather than entity based: the sync handler
/// replays **queued payloads** verbatim (that is what makes retries
/// idempotent), and a pull returns rows for the repository to merge. Full
/// `Customer` objects live one layer up.
///
/// Visibility and write permission per role (admin: all rows; technician:
/// only customers of jobs assigned to them, read-only) are enforced by
/// **Supabase RLS** — the same statements are issued for every role, with the
/// public anon/publishable key. There is no client-side privilege escalation
/// and no service-role key anywhere in this app.
abstract interface class CustomersRemoteDataSource {
  /// All customers visible to the current user, ordered by name.
  Future<List<CustomerModel>> fetchAll();

  /// Inserts or replaces the row identified by `row['id']` (the
  /// client-generated stable UUID). Retrying a create therefore updates the
  /// same row instead of duplicating the customer.
  Future<void> upsertRow(Map<String, Object?> row);

  /// Applies [changes] to the row with [id].
  ///
  /// Returns `false` when the row does not (or no longer) exists, so the
  /// sync handler can fail the operation instead of pretending success.
  Future<bool> updateRow({
    required String id,
    required Map<String, Object?> changes,
  });

  /// Deletes the row with [id].
  ///
  /// Returns `false` when the row was already gone remotely — also the
  /// *desired* end state for a delete, hence `true`/`false` is information,
  /// not an error.
  Future<bool> deleteRow(String id);
}

class CustomersRemoteDataSourceImpl implements CustomersRemoteDataSource {
  const CustomersRemoteDataSourceImpl(this.supabase);

  final SupabaseClient supabase;

  /// Exactly the real columns of `public.customers` (no invented fields).
  static const String _selectClause =
      'id, name, phone, email, address, city, postal_code, notes, '
      'created_at, updated_at';

  @override
  Future<List<CustomerModel>> fetchAll() async {
    final List<Map<String, dynamic>> rows = await supabase
        .from('customers')
        .select(_selectClause)
        .order('name', ascending: true)
        .order('id', ascending: true);

    return rows
        .map(
          (Map<String, dynamic> row) =>
              CustomerModel.fromRemoteRow(row as Map<String, Object?>),
        )
        .toList();
  }

  @override
  Future<void> upsertRow(Map<String, Object?> row) async {
    await supabase
        .from('customers')
        .upsert(Map<String, dynamic>.from(row), onConflict: 'id');
  }

  @override
  Future<bool> updateRow({
    required String id,
    required Map<String, Object?> changes,
  }) async {
    final List<Map<String, dynamic>> affected = await supabase
        .from('customers')
        .update(Map<String, dynamic>.from(changes))
        .eq('id', id)
        .select('id');

    return affected.isNotEmpty;
  }

  @override
  Future<bool> deleteRow(String id) async {
    final List<Map<String, dynamic>> affected = await supabase
        .from('customers')
        .delete()
        .eq('id', id)
        .select('id');

    return affected.isNotEmpty;
  }
}
