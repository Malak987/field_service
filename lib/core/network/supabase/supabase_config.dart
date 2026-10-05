/// Centralized Supabase connection configuration.
///
/// Security rules:
/// * Only the public/publishable key may ever be referenced here.
/// * Never include a `service_role` key inside the client application.
///
/// Deep-link redirect URIs are intentionally NOT declared here: they live in
/// [AuthDeepLinkConfig] (`core/deep_linking/auth_deep_link_config.dart`), the
/// single source of truth for the Supabase auth deep-link scheme and hosts.
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://atxeoquqxdverwgsrzki.supabase.co',
  );

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_C9Sv6RLF800olCo4mFWVDw_V3NP0gbz',
  );
}
