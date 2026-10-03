import 'package:equatable/equatable.dart';

/// Kind of local change that must eventually be replayed on the backend.
enum SyncOperationType {
  /// The entity was created offline.
  create,

  /// The entity was modified offline.
  update,

  /// The entity was deleted offline.
  delete,
}

/// The aggregate a [SyncOperation] refers to.
///
/// Deliberately explicit rather than a table name: the local schema may change
/// (a table may be split or renamed) without changing the meaning of the queue.
enum SyncEntityType {
  /// A renovation / installation / maintenance job.
  job,

  /// A file attached to a job (photo, signature, document) — the operation
  /// refers to its metadata, the upload of the bytes is part of the payload.
  jobFile,

  /// A customer record.
  customer,

  /// A technician or admin record.
  employee,
}

/// Lifecycle of a queued operation.
enum SyncOperationStatus {
  /// Waiting to be pushed.
  pending,

  /// Currently being pushed; prevents two runs from sending the same change.
  inProgress,

  /// Accepted by the backend.
  synced,

  /// Push failed and was postponed; [SyncOperation.attempts] was incremented.
  failed,
}

/// A single local change waiting to be pushed to the backend.
///
/// This is the unit of work of the offline-first flow documented in
/// `ARCHITECTURE.md`:
///
/// ```text
/// local write -> sync queue -> internet available -> push -> mark as synced
/// ```
///
/// Phase 3 status: the model is defined so that the queue contract
/// (`SyncQueue`), the future Drift table and the future push implementation
/// agree on one shape. Nothing writes or reads it yet.
class SyncOperation extends Equatable {
  const SyncOperation({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.status = SyncOperationStatus.pending,
    this.lastAttemptAt,
    this.errorMessage,
  });

  /// Identifier of the operation itself, generated locally with `uuid` so it
  /// exists before the backend has ever seen the record.
  final String id;

  /// Aggregate this change belongs to.
  final SyncEntityType entityType;

  /// Identifier of the affected entity. Client generated for the same reason as
  /// [id]: a technician can create a job in a basement with no signal.
  final String entityId;

  /// What happened locally.
  final SyncOperationType type;

  /// JSON-serialisable snapshot of the change, ready to be sent.
  ///
  /// Typed as `Map<String, Object?>` rather than a raw `String` so it can be
  /// validated and inspected before serialisation, and rather than `dynamic` so
  /// the compiler still helps.
  final Map<String, Object?> payload;

  /// When the local change happened (ordering key of the queue).
  final DateTime createdAt;

  /// How many push attempts already failed; drives retry/backoff and lets the
  /// UI flag operations that need attention.
  final int attempts;

  /// Current lifecycle state.
  final SyncOperationStatus status;

  /// When the last attempt was made, if any.
  final DateTime? lastAttemptAt;

  /// Error of the last failed attempt, kept for diagnostics.
  final String? errorMessage;

  /// Returns a copy with the given fields replaced.
  SyncOperation copyWith({
    SyncOperationStatus? status,
    int? attempts,
    DateTime? lastAttemptAt,
    String? errorMessage,
  }) {
    return SyncOperation(
      id: id,
      entityType: entityType,
      entityId: entityId,
      type: type,
      payload: payload,
      createdAt: createdAt,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    id,
    entityType,
    entityId,
    type,
    payload,
    createdAt,
    status,
    attempts,
    lastAttemptAt,
    errorMessage,
  ];
}
