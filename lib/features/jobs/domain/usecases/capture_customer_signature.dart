import 'dart:typed_data';

import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Captures the customer's signature for a job: the PNG rendered from the
/// on-screen drawing is persisted into stable app-owned storage, a local
/// `job_files` record (`file_type = 'signature'`) is created with an
/// automatic capture timestamp and the upload is queued in the durable sync
/// queue.
///
/// Offline-first by construction — nothing here touches the network. The
/// shared sync engine pushes the file when connectivity exists; the server
/// RPC is idempotent, so replays never duplicate the file row or its
/// `signature_captured` event.
///
/// Authorization is server-side: the RPC refuses jobs that are not assigned
/// to the caller's active employee, jobs that are not `in_progress`, and
/// callers that are not technicians (admins never capture).
class CaptureCustomerSignature {
  const CaptureCustomerSignature(this._repository);

  final JobsRepository _repository;

  /// Validates and captures the signature.
  ///
  /// [jobId] — the job the signature belongs to.
  /// [signatureImage] — the rendered PNG bytes of the customer's drawing.
  /// An empty image is rejected with an [ArgumentError] — an empty
  /// signature is never stored or queued.
  ///
  /// Returns the stable file id of the registered signature.
  Future<String> call({
    required String jobId,
    required Uint8List signatureImage,
  }) {
    if (signatureImage.isEmpty) {
      throw ArgumentError.value(
        signatureImage,
        'signatureImage',
        'The signature image is empty',
      );
    }
    return _repository.captureCustomerSignature(
      jobId: jobId,
      signatureImage: signatureImage,
    );
  }
}
