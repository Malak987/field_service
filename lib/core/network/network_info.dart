/// Answers a single question: *can this device reach the internet right now?*
///
/// This is the only connectivity concept the rest of the application knows
/// about. Data sources use it to choose between remote and local reads/writes,
/// and the sync engine (later phase) uses it to decide whether the queue can be
/// flushed — none of them import `connectivity_plus` or
/// `internet_connection_checker_plus` directly.
///
/// Keeping it as a plain Dart interface is what allows the backend (Supabase)
/// and the sync engine to be added later without touching the Domain layer.
abstract interface class NetworkInfo {
  /// Whether usable internet access is available at this moment.
  ///
  /// This performs a real reachability probe, so it may take a moment; prefer
  /// [onConnectionChanged] to react to changes rather than polling.
  Future<bool> get isConnected;

  /// Emits the current status immediately, then again on every change.
  Stream<bool> get onConnectionChanged;
}
