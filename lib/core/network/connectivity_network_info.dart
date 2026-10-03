import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:field_service/core/network/network_info.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

/// [NetworkInfo] implementation combining two signals:
///
/// * `connectivity_plus` — is there a network interface at all (Wi-Fi, mobile)?
///   Fast, but a connected Wi-Fi router does not mean the internet is reachable.
/// * `internet_connection_checker_plus` — is external routing actually working?
///   Slower, which is why it is only probed once an interface exists.
///
/// Both answers are combined on purpose: a technician connected to a customer's
/// router without internet must be treated as offline, otherwise the sync engine
/// would try to push and fail with confusing errors instead of queueing.
///
/// Both collaborators are injectable, so the class is unit-testable without a
/// device and without touching platform channels.
class ConnectivityNetworkInfo implements NetworkInfo {
  ConnectivityNetworkInfo({
    Connectivity? connectivity,
    InternetConnection? internetConnection,
  }) : _connectivity = connectivity ?? Connectivity(),
       _internetConnection = internetConnection ?? InternetConnection();

  final Connectivity _connectivity;
  final InternetConnection _internetConnection;

  @override
  Future<bool> get isConnected async {
    final List<ConnectivityResult> results = await _connectivity
        .checkConnectivity();
    final bool hasInterface = results.any(
      (ConnectivityResult result) => result != ConnectivityResult.none,
    );

    if (!hasInterface) {
      return false;
    }

    return _internetConnection.hasInternetAccess;
  }

  @override
  Stream<bool> get onConnectionChanged async* {
    // Emit the current status first so listeners never wait for a change before
    // learning whether they are online.
    yield await isConnected;

    await for (final _ in _connectivity.onConnectivityChanged) {
      // Interface changes are only a hint; the real reachability probe decides.
      yield await isConnected;
    }
  }
}
