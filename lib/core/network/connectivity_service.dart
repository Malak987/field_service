import 'dart:async';

import 'package:field_service/core/network/network_info.dart';

/// The two states the rest of the application distinguishes.
///
/// "online" means *usable internet access* — not merely "a network interface
/// is connected". A technician on a customer's router without internet is
/// `offline` for everything in this app (see [NetworkInfo] for the combined
/// probe that implements that definition).
enum ConnectivityStatus { online, offline }

/// Long-lived connectivity state for the sync engine and the UI.
///
/// Wraps the one-shot [NetworkInfo] contract into a managed, cached,
/// broadcast stream:
///
/// * [start] subscribes exactly once (idempotent) and begins emitting,
/// * [current] is always available — even before the first probe resolves —
///   so no UI can block on connectivity,
/// * [onStatusChanged] emits actual transitions (online ↔ offline) once
///   monitoring has started, so the [SyncManager] can simply trigger a run
///   when the status becomes [ConnectivityStatus.online]. Listeners that
///   attach late read [current] for the already-resolved state — the
///   [SyncManager] does exactly that on [start].
///
/// The service itself performs no probing: the policy (interface check plus
/// real reachability probe) lives in the injected [NetworkInfo]
/// implementation (`ConnectivityNetworkInfo`).
class ConnectivityService {
  ConnectivityService({required this._networkInfo});

  final NetworkInfo _networkInfo;
  final StreamController<ConnectivityStatus> _controller =
      StreamController<ConnectivityStatus>.broadcast();

  StreamSubscription<bool>? _subscription;
  ConnectivityStatus _current = ConnectivityStatus.offline;
  bool _started = false;

  /// The last known status. Defaults to [ConnectivityStatus.offline] — the
  /// safe assumption: never attempt a network push before the first probe.
  ConnectivityStatus get current => _current;

  /// Convenience for the sync engine: `true` only when usable internet
  /// access is confirmed.
  bool get isOnline => _current == ConnectivityStatus.online;

  /// Emits the current status on first listen, then every transition
  /// (online → offline, offline → online).
  Stream<ConnectivityStatus> get onStatusChanged => _controller.stream;

  /// Begins monitoring. Safe to call repeatedly; the first call wins.
  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    _subscription = _networkInfo.onConnectionChanged.listen(
      (bool hasInternet) {
        _update(
          hasInternet ? ConnectivityStatus.online : ConnectivityStatus.offline,
        );
      },
      onError: (Object error) {
        // A broken probe must not wedge the app: treat as offline and keep
        // listening for the next event.
        _update(ConnectivityStatus.offline);
      },
    );
  }

  void _update(ConnectivityStatus status) {
    if (_controller.isClosed) {
      return;
    }
    if (status == _current) {
      return; // Only transitions are emitted.
    }
    _current = status;
    _controller.add(status);
  }

  /// Stops monitoring and cancels the subscription.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
    await _controller.close();
  }
}
