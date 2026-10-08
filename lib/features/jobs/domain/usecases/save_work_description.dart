import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Use case: the TECHNICIAN saves what was actually done on the job.
///
/// This is the execution-side record — strictly separate from the admin's
/// customer request (`jobs.description`), which this use case never writes.
///
/// Domain validation happens here (and is mirrored server-side by the
/// `save_work_description` RPC): the text is trimmed, must not be empty and
/// must not exceed [maxLength]. Input is rejected with an [ArgumentError]
/// rather than silently truncated — the caller decides how to surface it.
class SaveWorkDescription {
  const SaveWorkDescription(this._repository);

  final JobsRepository _repository;

  /// Maximum accepted length after trimming (one shared constant).
  static int get maxLength => JobsRepository.maxWorkDescriptionLength;

  /// Trims and validates [workDescription]; returns the clean text.
  ///
  /// Throws [ArgumentError] when the text is empty/blank or too long.
  static String validate(String? workDescription) {
    final String clean = (workDescription ?? '').trim();
    if (clean.isEmpty) {
      throw ArgumentError.value(
        workDescription,
        'workDescription',
        'Work description cannot be empty',
      );
    }
    if (clean.length > maxLength) {
      throw ArgumentError.value(
        workDescription,
        'workDescription',
        'Work description exceeds $maxLength characters',
      );
    }
    return clean;
  }

  /// Saves the validated work description for [jobId] — offline-first via
  /// the durable sync queue; the server RPC is the final authority.
  Future<void> call({required String jobId, required String workDescription}) {
    final String clean = validate(workDescription);
    return _repository.saveWorkDescription(
      jobId: jobId,
      workDescription: clean,
    );
  }
}
