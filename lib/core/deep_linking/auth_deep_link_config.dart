import 'package:flutter/foundation.dart';

/// Single source of truth for the Supabase authentication deep links.
///
/// Supabase brings the user back to the app after email confirmation and
/// password recovery. On mobile/desktop it does this through a **custom URL
/// scheme**, and on the web through the **application's own origin**.
///
/// Every redirect URI handed to Supabase (`signUp`'s `emailRedirectTo`,
/// `resetPasswordForEmail`'s `redirectTo`) and the predicate that recognises
/// incoming callbacks MUST be derived from this class, so the scheme, the two
/// callback hosts and the full URLs are declared exactly once and never
/// hardcoded anywhere else in the codebase.
///
/// The two callback hosts are also registered as URL types on the native side:
///
///   * Android: `android/app/src/main/AndroidManifest.xml` (intent-filter)
///   * iOS:     `ios/Runner/Info.plist` (`CFBundleURLTypes`)
///
/// Keep those native registrations in sync with [scheme] and [callbackHosts].
abstract final class AuthDeepLinkConfig {
  /// Custom URL scheme the native apps are registered to receive.
  ///
  /// This is the part before `://`. It must match `android:scheme` in
  /// AndroidManifest.xml and the entry in `CFBundleURLSchemes` in Info.plist.
  static const String scheme = 'fieldservice';

  /// Host used by Supabase **email-confirmation** (sign up) links.
  static const String confirmCallbackHost = 'auth-callback';

  /// Host used by Supabase **password-recovery** links.
  static const String resetCallbackHost = 'reset-password';

  /// Every host the app is expected to accept as a Supabase auth callback.
  static const Set<String> callbackHosts = <String>{
    confirmCallbackHost,
    resetCallbackHost,
  };

  // Mobile/desktop callback targets (custom scheme).
  static const String _mobileConfirmRedirect = 'fieldservice://auth-callback';
  static const String _mobileResetRedirect = 'fieldservice://reset-password';

  /// Redirect target for the **email-confirmation** link
  /// (`signUp`'s `emailRedirectTo`).
  ///
  /// Mobile/desktop: the custom-scheme callback. Web: the application origin
  /// so the running Supabase client can read the code from its own URL.
  static String get emailConfirmationRedirectTo {
    if (kIsWeb) {
      return Uri.base.resolve('/$confirmCallbackHost').toString();
    }
    return _mobileConfirmRedirect;
  }

  /// Redirect target for the **password-recovery** link
  /// (`resetPasswordForEmail`'s `redirectTo`).
  static String get passwordResetRedirectTo {
    if (kIsWeb) {
      return Uri.base.resolve('/$resetCallbackHost').toString();
    }
    return _mobileResetRedirect;
  }

  /// Supabase deep-link predicate: returns `true` only for URIs this app
  /// registered as Supabase auth callbacks.
  ///
  /// Passed to `Supabase.initialize` through
  /// `FlutterAuthClientOptions.detectSessionInUriPredicate` so the client
  /// exchanges exactly — and only — these links for a session. This keeps the
  /// recognition logic tied to the same single source of truth that produces
  /// the redirect URIs.
  static bool isAuthCallbackUriPredicate(Uri uri) {
    // Mobile / desktop: `fieldservice://auth-callback` or
    // `fieldservice://reset-password` — the callback name is the host.
    if (uri.scheme == scheme && callbackHosts.contains(uri.host)) {
      return true;
    }

    // Web: the browser redirects back to the app's own origin, so the callback
    // name lives in the path (`/auth-callback`, `/reset-password`).
    final String path = uri.path;
    return callbackHosts.any(
      (String host) => path == '/$host' || path.startsWith('/$host/'),
    );
  }
}
