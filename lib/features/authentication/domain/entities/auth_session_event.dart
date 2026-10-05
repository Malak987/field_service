/// Domain-level authentication lifecycle event emitted by the auth provider.
///
/// Decouples the Domain and Presentation layers from Supabase's concrete
/// `AuthChangeEvent` while still allowing the application to react to
/// password-recovery deep links and session invalidations.
enum AuthSessionEvent {
  initialSession,
  signedIn,
  signedOut,
  passwordRecovery,
  tokenRefreshed,
  userUpdated,
}
