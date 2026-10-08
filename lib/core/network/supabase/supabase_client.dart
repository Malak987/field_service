import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseClientProvider {
  SupabaseClientProvider._();

  static SupabaseClient get client => Supabase.instance.client;
}
