import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Captures an after photo for a job: the finished-site counterpart of
/// [AddBeforePhoto] — copies the picked image into stable app-owned storage,
/// creates the local `job_files` record (`file_type = 'after'`) with an
/// automatic capture timestamp and queues the upload in the durable sync
/// queue.
///
/// Offline-first by construction — nothing here touches the network. The
/// shared sync engine pushes the file when connectivity exists; the server
/// RPC is idempotent, so replays never duplicate the photo or its event.
///
/// Authorization is server-side: the RPC refuses jobs that are not assigned
/// to the caller's active employee, jobs that are not `in_progress`, and
/// callers that are not technicians (admins never capture).
class AddAfterPhoto {
  const AddAfterPhoto(this._repository);

  final JobsRepository _repository;

  /// [jobId] — the job the photo belongs to.
  /// [pickedFilePath] — absolute path of the image just picked from the
  /// camera/gallery. The bytes are copied immediately; the picked (possibly
  /// temporary) file is never relied upon afterwards.
  ///
  /// Returns the stable file id of the registered photo.
  Future<String> call({required String jobId, required String pickedFilePath}) {
    return _repository.addAfterPhoto(
      jobId: jobId,
      pickedFilePath: pickedFilePath,
    );
  }
}
