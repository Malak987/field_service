import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseClientProvider {
  SupabaseClientProvider._();

  static SupabaseClient get client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return SupabaseClient('https://placeholder.supabase.co', 'placeholder-key');
    }
  }
}
