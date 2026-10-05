import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns raw push errors into short, user-safe, stable messages.
///
/// Two rules:
/// * **Persistence** stores the mapped message in `sync_queue.last_error` —
///   never the raw exception text (it can carry URLs, table names and, in
///   edge cases, key fragments).
/// * **UI** only ever shows these mapped messages; a raw `PostgrestException`
///   is never a user-facing string.
///
/// This class is the single place in the offline layer that knows Supabase's
/// exception types; everything else stays backend-agnostic.
class SyncErrorMapper {
  const SyncErrorMapper();

  /// Maps [error] to a short, stable, user-safe description.
  String toSafeMessage(Object error) {
    if (error is AuthException) {
      return 'Authentication required. Please sign in again.';
    }

    if (error is PostgrestException) {
      return _mapPostgrest(error);
    }

    if (error is SocketException) {
      return 'Network error: no response from the backend.';
    }

    if (error is TimeoutException) {
      return 'Network error: the backend took too long to answer.';
    }

    if (error is FormatException) {
      return 'The stored change could not be read. Please contact support.';
    }

    if (error is StateError || error is ArgumentError) {
      // Short, developer-safe messages; these indicate app-side issues, not
      // user errors. (StateError/ArgumentError toString() is the message.)
      return 'Sync problem: $error';
    }

    // Default: name only. The raw message is deliberately not included
    // (it may contain URLs or backend internals).
    return 'Sync failed (${error.runtimeType}).';
  }

  String _mapPostgrest(PostgrestException error) {
    switch (error.code) {
      // RLS denial / insufficient privilege.
      case '42501':
      case '42500':
        return 'The backend rules rejected this change (permission denied).';
      // Unique constraint violation — the record exists remotely.
      case '23505':
        return 'A conflicting record already exists on the backend.';
      // FK violation — the referenced record does not exist remotely yet.
      case '23503':
        return 'A referenced record does not exist on the backend yet.';
      case '23502':
        return 'The change is missing a required value.';
      default:
        return 'The backend rejected this change (code ${error.code}).';
    }
  }
}
