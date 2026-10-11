import 'package:equatable/equatable.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';

/// How a technician-initiated "customer & job" creation ended.
enum TechnicianJobCreationStatus {
  /// The SERVER confirmed the creation: [TechnicianJobCreation.job] is the
  /// authoritative row, including the database-generated `job_number`.
  created,

  /// The device was offline. The creation is durably queued in the shared
  /// sync queue and will be pushed when connectivity returns — the server
  /// has NOT seen it yet, so no job number exists and nothing may be
  /// reported as "saved on the server".
  queuedForSync,
}

/// Outcome of one "Create Customer & Job" (or "Create Job") submission.
///
/// Typed on purpose so the UI can distinguish "the server confirmed it" from
/// "it is safely stored on this device and will sync" — those two need
/// different messages and different navigation, and conflating them would be
/// a false success report.
class TechnicianJobCreation extends Equatable {
  const TechnicianJobCreation._({
    required this.status,
    required this.jobId,
    this.job,
  });

  /// The server confirmed the creation and returned the job row.
  factory TechnicianJobCreation.created(Job job) {
    return TechnicianJobCreation._(
      status: TechnicianJobCreationStatus.created,
      jobId: job.id,
      job: job,
    );
  }

  /// The creation is queued locally (offline) and awaits the next sync.
  const TechnicianJobCreation.queued({required this.jobId})
    : status = TechnicianJobCreationStatus.queuedForSync,
      job = null;

  final TechnicianJobCreationStatus status;

  /// The stable, client-generated `jobs.id` of this creation.
  ///
  /// Known in BOTH states: it is the idempotency key of the queued operation
  /// and the id the server row carries once the push lands.
  final String jobId;

  /// The authoritative job row — non-null only when the server confirmed.
  final Job? job;

  /// Whether the server confirmed the creation.
  bool get isCreated => status == TechnicianJobCreationStatus.created;

  /// Whether the creation is still waiting for a sync.
  bool get isPendingSync => status == TechnicianJobCreationStatus.queuedForSync;

  /// The database-generated `job_number`, when the server confirmed.
  int? get jobNumber => job?.jobNumber;

  @override
  List<Object?> get props => <Object?>[status, jobId, job];
}
