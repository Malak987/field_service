import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Captures a before photo for a job: copies the picked image into stable
/// app-owned storage, creates the local `job_files` record with an automatic
/// capture timestamp and queues the upload in the durable sync queue.
///
/// Offline-first by construction — nothing here touches the network. The
/// shared sync engine pushes the file when connectivity exists; the server
/// RPC is idempotent, so replays never duplicate the photo or its event.
///
/// Authorization is server-side: the RPC refuses jobs that are not assigned
/// to the caller's active employee and jobs that are not `in_progress`.
class AddBeforePhoto {
  const AddBeforePhoto(this._repository);

  final JobsRepository _repository;

  /// [jobId] — the job the photo belongs to.
  /// [pickedFilePath] — absolute path of the image just picked from the
  /// camera/gallery. The bytes are copied immediately; the picked (possibly
  /// temporary) file is never relied upon afterwards.
  ///
  /// Returns the stable file id of the registered photo.
  Future<String> call({required String jobId, required String pickedFilePath}) {
    return _repository.addBeforePhoto(
      jobId: jobId,
      pickedFilePath: pickedFilePath,
    );
  }
}
