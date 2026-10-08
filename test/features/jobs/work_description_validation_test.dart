import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';
import 'package:field_service/features/jobs/domain/usecases/save_work_description.dart';
import 'package:flutter_test/flutter_test.dart';

/// Domain validation of the Work Description step.
///
/// The `save_work_description` RPC mirrors these exact rules server-side;
/// the client-side validation is defense in depth that keeps invalid text
/// out of the durable sync queue entirely.
void main() {
  group('SaveWorkDescription.validate', () {
    test('accepts plain text unchanged', () {
      expect(
        SaveWorkDescription.validate('Installed the new countertop.'),
        'Installed the new countertop.',
      );
    });

    test('trims surrounding whitespace before returning', () {
      expect(
        SaveWorkDescription.validate('  Sealed all joints.  \n'),
        'Sealed all joints.',
      );
    });

    test('rejects null as empty', () {
      expect(() => SaveWorkDescription.validate(null), throwsArgumentError);
    });

    test('rejects an empty string', () {
      expect(() => SaveWorkDescription.validate(''), throwsArgumentError);
    });

    test('rejects whitespace-only text (no silent acceptance)', () {
      expect(
        () => SaveWorkDescription.validate('   \n\t  '),
        throwsArgumentError,
      );
    });

    test('accepts text at exactly the maximum length', () {
      final String max = 'a' * SaveWorkDescription.maxLength;
      expect(SaveWorkDescription.validate(max), max);
    });

    test('rejects text one character over the maximum', () {
      final String tooLong = 'a' * (SaveWorkDescription.maxLength + 1);
      expect(() => SaveWorkDescription.validate(tooLong), throwsArgumentError);
    });

    test('the maximum length is the one shared constant (4000)', () {
      expect(
        SaveWorkDescription.maxLength,
        JobsRepository.maxWorkDescriptionLength,
      );
      expect(SaveWorkDescription.maxLength, 4000);
    });
  });

  group('Job.workDescription', () {
    Job job() => Job(
      id: 'job-1',
      jobNumber: 101,
      customerId: 'cust-1',
      assignedEmployeeId: 'emp-tech-1',
      jobType: 'kitchen_renovation',
      description: 'Customer request: renovate the kitchen.',
      status: const JobStatus(JobStatus.inProgress),
      startedAt: DateTime.utc(2026, 10, 6, 9, 30),
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
      expiresAt: DateTime.utc(2026, 12, 1),
    );

    test('defaults to null — nothing merged with the customer request', () {
      expect(job().workDescription, isNull);
      // The admin's customer request stays in `description`, untouched.
      expect(job().description, 'Customer request: renovate the kitchen.');
    });

    test('copyWith stores the work description separately', () {
      final Job updated = job().copyWith(workDescription: 'Did the work.');
      expect(updated.workDescription, 'Did the work.');
      expect(updated.description, 'Customer request: renovate the kitchen.');
    });

    test('copyWith can clear the work description explicitly', () {
      final Job withText = job().copyWith(workDescription: 'Some text.');
      final Job cleared = withText.copyWith(clearWorkDescription: true);
      expect(cleared.workDescription, isNull);
    });
  });

  // The interface surface used by the repository/fakes — compile-time guard
  // that the contract stays minimal.
  test('JobsRepository declares the max length constant', () {
    expect(JobsRepository.maxWorkDescriptionLength, 4000);
  });
}
