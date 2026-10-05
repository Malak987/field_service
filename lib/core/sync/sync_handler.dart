import 'package:field_service/core/sync/sync_operation.dart';

/// Outcome of one remote push attempt.
class RemotePushResult {
  /// The backend accepted the change.
  const RemotePushResult.ok() : success = true, reason = null;

  /// The change was not (yet) accepted; [reason] must be a short,
  /// user-safe description (see `SyncErrorMapper`) — never a raw exception.
  const RemotePushResult.failure(this.reason) : success = false;

  final bool success;
  final String? reason;
}

/// Pushes queued operations of one entity type to the backend.
///
/// Contract:
/// * **Idempotent.** Retrying the same [SyncOperation] must not create
///   duplicate logical records. Implementations achieve this by upserting on
///   the client-generated entity id that is already contained in the
///   operation (its payload) — never by generating a new id per attempt.
/// * **One operation per call.** The [SyncManager] drives ordering, claims
///   and state transitions; the handler only performs the remote write.
/// * **No queue access.** Handlers must not touch the [SyncQueue]; the
///   manager owns its state machine.
abstract interface class SyncOperationHandler {
  /// Pushes [operation] to the backend.
  ///
  /// Returns [RemotePushResult.failure] (instead of throwing) for expected
  /// failure modes such as RLS denials, conflicts or rate limits; throwing is
  /// reserved for programming errors, and is treated as a failed attempt by
  /// the manager as well.
  Future<RemotePushResult> push(SyncOperation operation);
}

/// Lookup from entity type to handler.
///
/// Features register their handlers here when they integrate (customers,
/// jobs, job events, job files). An operation whose type has no registered
/// handler is **failed with a clear, persisted error** — never silently
/// dropped and never silently "synced".
abstract interface class SyncHandlerRegistry {
  /// The handler for [type], or `null` when the entity type is not
  /// integrated yet.
  SyncOperationHandler? handlerFor(SyncEntityType type);
}

/// Growable registry; the single instance registered in GetIt.
class MutableSyncHandlerRegistry implements SyncHandlerRegistry {
  final Map<SyncEntityType, SyncOperationHandler> _handlers =
      <SyncEntityType, SyncOperationHandler>{};
  final Map<SyncEntityType, SyncOperationHandler Function()> _factories =
      <SyncEntityType, SyncOperationHandler Function()>{};

  /// Registers (or replaces) an already-created handler for [type].
  void register(SyncEntityType type, SyncOperationHandler handler) {
    _factories.remove(type);
    _handlers[type] = handler;
  }

  /// Registers a lazy handler factory for [type].
  ///
  /// Useful for feature modules whose handler transitively depends on runtime
  /// services (such as an initialized Supabase client). The feature can join
  /// the sync registry while the dependency graph is being assembled, without
  /// eagerly opening a database or constructing the backend client.
  void registerFactory(
    SyncEntityType type,
    SyncOperationHandler Function() createHandler,
  ) {
    _handlers.remove(type);
    _factories[type] = createHandler;
  }

  @override
  SyncOperationHandler? handlerFor(SyncEntityType type) {
    return _handlers[type] ?? _factories[type]?.call();
  }

  /// Diagnostic: which entity types are currently integrated.
  Set<SyncEntityType> get registeredTypes =>
      Set.unmodifiable(<SyncEntityType>{..._handlers.keys, ..._factories.keys});
}
