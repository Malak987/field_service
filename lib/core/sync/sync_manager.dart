import 'dart:async';

import 'package:field_service/core/network/connectivity_service.dart';
import 'package:field_service/core/sync/sync_error_mapper.dart';
import 'package:field_service/core/sync/sync_handler.dart';
import 'package:field_service/core/sync/sync_operation.dart';
import 'package:field_service/core/sync/sync_processor.dart';
import 'package:field_service/core/sync/sync_queue.dart';
import 'package:field_service/core/sync/sync_status.dart';
import 'package:field_service/core/utils/logger.dart';

/// The offline-first push engine.
///
/// Responsibilities (and nothing else):
///
/// 1. Watches [ConnectivityService] and triggers a run when usable internet
///    returns.
/// 2. Reads the queue oldest-first, **dependency-aware**.
/// 3. Claims each operation (`pending` → `inProgress`) so two runs can never
///    process the same change.
/// 4. Pushes through the registered [SyncOperationHandler] for the entity
///    type, then transitions the row to `synced` or `failed` (with
///    attempt counter and sanitised error persisted).
/// 5. Keeps going when one operation fails — the rest of the queue is not
///    blocked by a single bad operation.
/// 6. Pauses immediately when the internet disappears mid-run: the in-flight
///    operation is either resolved or released back to `pending`; the queue
///    is never cleared.
/// 7. On [start] recovers operations left `inProgress` by a killed app.
///
/// True OS-level background execution is not implemented yet; the manager is
/// deliberately structured so a background isolate (or platform scheduler)
/// can later call [processPendingOperations] without touching any other part
/// of the architecture.
class SyncManager implements SyncProcessor {
  SyncManager({
    required this._queue,
    required this._connectivity,
    required this._handlers,
    SyncErrorMapper? errorMapper,
  }) : _errorMapper = errorMapper ?? const SyncErrorMapper();

  final SyncQueue _queue;
  final ConnectivityService _connectivity;
  final SyncHandlerRegistry _handlers;
  final SyncErrorMapper _errorMapper;

  final StreamController<SyncHealth> _healthController =
      StreamController<SyncHealth>.broadcast();
  StreamSubscription<ConnectivityStatus>? _connectivitySubscription;

  bool _started = false;
  bool _syncing = false;
  SyncHealth _lastHealth = SyncHealth(
    networkStatus: ConnectivityStatus.offline,
  );

  // --- Public state -------------------------------------------------------------

  @override
  bool get isSyncing => _syncing;

  /// The most recent health snapshot (always available, no await needed).
  SyncHealth get currentHealth => _lastHealth;

  /// Health changes: sync start/stop, queue count changes, failures, and
  /// connectivity transitions.
  Stream<SyncHealth> get onHealthChanged => _healthController.stream;

  // --- Lifecycle ------------------------------------------------------------------

  /// Starts connectivity monitoring and begins listening for the internet
  /// returning. Safe to call repeatedly; the first call wins.
  ///
  /// Non-blocking in practice: the first internet probe happens in the
  /// background; the app is fully usable before it resolves.
  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    // Crash recovery first: a run interrupted by a force-quit may have left
    // rows `inProgress`; they become `pending` again so nothing is stuck.
    final int recovered = await _queue.recoverInFlight();
    if (recovered > 0) {
      AppLogger.info('Sync: recovered $recovered interrupted operation(s).');
    }

    await _connectivity.start();

    _connectivitySubscription = _connectivity.onStatusChanged.listen(
      (ConnectivityStatus status) {
        _lastHealth = _lastHealth.copyWithNetworkStatus(status);
        _emitHealth();

        if (status == ConnectivityStatus.online) {
          unawaited(processPendingOperations());
        }
      },
    );

    // Reflect the already-resolved connectivity state (if any) in the health.
    _lastHealth = _lastHealth.copyWithNetworkStatus(_connectivity.current);
    _emitHealth();

    if (_connectivity.isOnline) {
      unawaited(processPendingOperations());
    }
  }

  /// Releases resources. Used by tests; the app keeps one engine for life.
  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _started = false;
    await _healthController.close();
  }

  // --- Sync runs -------------------------------------------------------------------

  @override
  Future<void> processPendingOperations() async {
    // Serialise runs: a second trigger (manual sync + connectivity event)
    // must never interleave with an active run — duplicate-processing guard
    // number one (queue-level claims are guard number two).
    if (_syncing) {
      return;
    }
    _syncing = true;
    _emitHealth();

    try {
      while (true) {
        // Pause check: no usable internet → stop. Everything not yet claimed
        // stays `pending`; a claimed operation is either already resolved or
        // released back below. The queue is never cleared.
        if (!_connectivity.isOnline) {
          break;
        }

        final SyncOperation? operation = await _queue.nextPending();
        if (operation == null) {
          break; // Queue drained.
        }

        final bool claimed = await _queue.claimPending(operation.id);
        if (!claimed) {
          continue; // Another run won it; take the next one.
        }

        // A run may take a moment; if the internet died while we were
        // deciding, release and stop instead of pushing into the void.
        if (!_connectivity.isOnline) {
          await _queue.releaseInFlight(operation.id);
          break;
        }

        final RemotePushResult result = await _push(operation);

        if (result.success) {
          await _queue.markSynced(operation.id);
        } else {
          // Persist the failure and **continue with the remaining
          // operations**: one bad record must not hold up everything else.
          await _queue.markFailed(
            operation.id,
            errorMessage: result.reason ?? 'Unknown error.',
          );
          _lastHealth = _lastHealth.copyWithLastError(result.reason);
        }

        _emitHealth();
      }
    } catch (error, stackTrace) {
      // The loop itself must never die silently: log loudly, surface in
      // health. Individual operation errors are handled above.
      AppLogger.warning(
        'Sync run aborted unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
      _lastHealth = _lastHealth.copyWithLastError(
        _errorMapper.toSafeMessage(error),
      );
    } finally {
      _syncing = false;
      _emitHealth();
    }
  }

  @override
  Future<void> retryFailedOperations() async {
    final int failed = await _queue.failedCount();
    if (failed == 0) {
      return;
    }
    // Keep attempt counters and error history; only the status changes.
    await _queue.requeueFailed();
    await processPendingOperations();
  }

  // --- Internals ---------------------------------------------------------------------

  Future<RemotePushResult> _push(SyncOperation operation) async {
    final SyncOperationHandler? handler =
        _handlers.handlerFor(operation.entityType);

    if (handler == null) {
      // Not a silent drop and not a fake success: the failure is persisted
      // with an explanation and stays retryable once the handler is
      // registered.
      return RemotePushResult.failure(
        'No remote handler registered for entity type '
        '"${operation.entityType.name}" yet.',
      );
    }

    try {
      return await handler.push(operation);
    } catch (error) {
      return RemotePushResult.failure(
        _errorMapper.toSafeMessage(error),
      );
    }
  }

  void _emitHealth() {
    if (_healthController.isClosed) {
      return;
    }
    // Refresh the counts so the emitted health reflects the queue after each
    // operation — this is what keeps the "N pending" indicator honest.
    unawaited(_refreshHealth());
  }

  Future<void> _refreshHealth() async {
    if (_healthController.isClosed) {
      return;
    }
    final int pendingCount = await _queue.pendingCount();
    final int failedCount = await _queue.failedCount();

    _lastHealth = SyncHealth(
      networkStatus: _connectivity.current,
      isSyncing: _syncing,
      pendingCount: pendingCount,
      failedCount: failedCount,
      lastError: _lastHealth.lastError,
    );

    if (!_healthController.isClosed) {
      _healthController.add(_lastHealth);
    }
  }
}

extension on SyncHealth {
  SyncHealth copyWithNetworkStatus(ConnectivityStatus status) {
    return SyncHealth(
      networkStatus: status,
      isSyncing: isSyncing,
      pendingCount: pendingCount,
      failedCount: failedCount,
      lastError: lastError,
    );
  }

  SyncHealth copyWithLastError(String? error) {
    return SyncHealth(
      networkStatus: networkStatus,
      isSyncing: isSyncing,
      pendingCount: pendingCount,
      failedCount: failedCount,
      lastError: error,
    );
  }
}
