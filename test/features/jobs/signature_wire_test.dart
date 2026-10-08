import 'dart:convert';
import 'dart:typed_data';

import 'package:field_service/core/database/tables/job_files_table.dart';
import 'package:field_service/features/jobs/data/datasources/job_files_remote_data_source.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';
import 'package:field_service/features/jobs/domain/usecases/capture_customer_signature.dart';
import 'package:field_service/app/di/injection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';

/// Wire-level contract tests of the Customer Signature data path plus the
/// domain validation of the capture use case.
///
/// The signature reuses the EXISTING registration RPC and Storage bucket:
/// * `register_job_file` is called with `p_file_type = 'signature'` and the
///   ORIGINAL capture time — never an employee id (the RPC resolves the
///   caller from auth.uid()) and never an upload/registration time;
/// * Storage paths follow the existing convention with the `signature`
///   segment: `jobs/{job_id}/signature/{file_id}{ext}`;
/// * the `job_files` read filters `file_type = 'signature'`.
void main() {
  Map<String, Object?> signatureRow() {
    // Mirrors the LIVE `public.job_files` schema EXACTLY (id, job_id,
    // file_type, storage_path, created_at, captured_at — nothing else). A
    // mapper expecting richer columns crashes the remote read and hides
    // every backend-registered file.
    return <String, Object?>{
      'id': 'file-signature-1',
      'job_id': 'job-mine',
      'file_type': 'signature',
      'storage_path': 'jobs/job-mine/signature/file-signature-1.png',
      'captured_at': '2026-10-07T15:40:00.000Z',
      'created_at': '2026-10-07T15:40:30.000Z',
    };
  }

  ({JobFilesRemoteDataSourceImpl remote, List<http.Request> requests})
  buildRemote(Object? Function(http.Request request) respond) {
    final List<http.Request> requests = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(respond(request)),
        200,
        headers: <String, String>{'content-type': 'application/json'},
        // The PostgREST client inspects `response.request` — attach it.
        request: request,
      );
    });

    final SupabaseClient supabase = SupabaseClient(
      'https://project.supabase.co',
      'test-anon-key',
      httpClient: client,
    );
    return (remote: JobFilesRemoteDataSourceImpl(supabase), requests: requests);
  }

  test('registerJobFile sends file_type "signature", no identity', () async {
    final built = buildRemote((http.Request request) => <Object?>[]);

    final DateTime capturedAt = DateTime.utc(2026, 10, 7, 15, 40);
    await built.remote.registerJobFile(
      fileId: 'file-signature-1',
      jobId: 'job-mine',
      fileType: JobFileType.signature.name,
      storagePath: 'jobs/job-mine/signature/file-signature-1.png',
      fileName: 'signature.png',
      mimeType: 'image/png',
      sizeBytes: 4321,
      capturedAt: capturedAt,
    );

    expect(built.requests, hasLength(1));
    final http.Request request = built.requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/rest/v1/rpc/register_job_file');

    final Map<String, dynamic> body =
        jsonDecode(request.body) as Map<String, dynamic>;

    // Exactly the RPC parameters — nothing else.
    expect(body.keys.toSet(), <String>{
      'p_file_id',
      'p_job_id',
      'p_file_type',
      'p_storage_path',
      'p_file_name',
      'p_mime_type',
      'p_size_bytes',
      'p_captured_at',
    });
    expect(body['p_file_id'], 'file-signature-1');
    expect(body['p_job_id'], 'job-mine');
    expect(body['p_file_type'], 'signature');
    expect(
      body['p_storage_path'],
      'jobs/job-mine/signature/file-signature-1.png',
    );
    expect(body['p_captured_at'], capturedAt.toIso8601String());

    // Authorization facts are NEVER sent: no employee id, no role.
    expect(
      body.keys.any((String key) => key.contains('employee')),
      isFalse,
      reason: 'the RPC resolves the caller from auth.uid() itself',
    );
    expect(body.keys.any((String key) => key.contains('role')), isFalse);
  });

  test('the storage path convention carries the signature segment', () {
    expect(
      JobFilesRemoteDataSource.storagePathFor(
        jobId: 'job-mine',
        fileType: JobFileType.signature.name,
        fileId: 'file-signature-1',
        extension: '.png',
      ),
      'jobs/job-mine/signature/file-signature-1.png',
    );
  });

  test(
    'getJobFilesByType filters the job_files read by file_type=signature',
    () async {
      final built = buildRemote(
        (http.Request request) => <Object?>[signatureRow()],
      );

      final List<JobFile> files = await built.remote.getJobFilesByType(
        'job-mine',
        'signature',
      );

      expect(built.requests, hasLength(1));
      final Uri uri = built.requests.single.url;
      expect(uri.path, '/rest/v1/job_files');
      expect(uri.queryParameters['job_id'], 'eq.job-mine');
      expect(uri.queryParameters['file_type'], 'eq.signature');

      expect(files, hasLength(1));
      expect(files.single.id, 'file-signature-1');
      expect(files.single.fileType, 'signature');
      expect(
        files.single.remotePath,
        'jobs/job-mine/signature/file-signature-1.png',
      );
      expect(
        files.single.capturedAt,
        DateTime.parse('2026-10-07T15:40:00.000Z'),
      );
    },
  );

  group('CaptureCustomerSignature validation', () {
    late AppTestHarness app;

    setUp(() => app = AppTestHarness());
    tearDown(() => app.dispose());

    test('rejects an empty signature, accepts valid bytes', () async {
      await app.configure(
        user: technicianUser,
        jobs: <Job>[
          Job(
            id: 'job-mine',
            jobNumber: 101,
            customerId: 'cust-1',
            assignedEmployeeId: 'emp-tech-1',
            jobType: 'kitchen_renovation',
            status: const JobStatus(JobStatus.inProgress),
            startedAt: DateTime.utc(2026, 10, 6, 9, 30),
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
            expiresAt: DateTime.utc(2026, 12, 1),
          ),
        ],
      );

      final capture = CaptureCustomerSignature(sl<JobsRepository>());

      // Empty drawing → refused BEFORE storage/queue (no silent success).
      await expectLater(
        () => capture(jobId: 'job-mine', signatureImage: Uint8List(0)),
        throwsArgumentError,
      );
      expect(app.signatureCapturedJobIds, isEmpty);

      // Valid bytes → accepted and registered server-side (fake).
      final String fileId = await capture(
        jobId: 'job-mine',
        signatureImage: Uint8List.fromList(<int>[1, 2, 3]),
      );
      expect(fileId, isNotEmpty);
      expect(app.signatureCapturedJobIds, <String>['job-mine']);
      expect(app.serverSignatures['job-mine'], hasLength(1));
      expect(app.serverSignatures['job-mine']!.single.fileType, 'signature');
    });
  });
}
