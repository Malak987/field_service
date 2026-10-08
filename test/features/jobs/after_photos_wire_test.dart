import 'dart:convert';

import 'package:field_service/core/database/tables/job_files_table.dart';
import 'package:field_service/features/jobs/data/datasources/job_files_remote_data_source.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wire-level contract tests of the After Photos data path.
///
/// The client reuses the EXISTING registration RPC and Storage bucket:
/// * `register_job_file` is called with `p_file_type = 'after'` and the
///   ORIGINAL capture time — never an employee id (the RPC resolves the
///   caller from auth.uid()) and never an upload/registration time;
/// * Storage paths follow the existing convention with the `after` segment:
///   `jobs/{job_id}/after/{file_id}{ext}`;
/// * the `job_files` read filters `file_type = 'after'` so before and after
///   photos never mix.
void main() {
  /// Mirrors the LIVE `public.job_files` schema EXACTLY: id, job_id,
  /// file_type, storage_path, created_at, captured_at — nothing else. There
  /// is no employee_id/file_name/mime_type/size_bytes on the backend; a
  /// mapper that expects them crashes the whole remote read and hides every
  /// backend-registered file (the "files disappear on another device" bug).
  Map<String, Object?> afterRow() {
    return <String, Object?>{
      'id': 'file-after-1',
      'job_id': 'job-mine',
      'file_type': 'after',
      'storage_path': 'jobs/job-mine/after/file-after-1.jpg',
      'captured_at': '2026-10-07T14:05:00.000Z',
      'created_at': '2026-10-07T14:05:30.000Z',
    };
  }

  ({JobFilesRemoteDataSourceImpl remote, List<http.Request> requests})
  buildRemote(Object? Function(http.Request request) respond) {
    final List<http.Request> requests = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      requests.add(request);
      final Object? body = respond(request);
      return http.Response(
        jsonEncode(body),
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

  group('domain type', () {
    test('JobFileType declares before AND after (no new file entity)', () {
      expect(JobFileType.values, contains(JobFileType.before));
      expect(JobFileType.values, contains(JobFileType.after));
      expect(JobFileType.after.name, 'after');
    });

    test('the storage path convention carries the after segment', () {
      expect(
        JobFilesRemoteDataSource.storagePathFor(
          jobId: 'job-mine',
          fileType: JobFileType.after.name,
          fileId: 'file-after-1',
          extension: '.jpg',
        ),
        'jobs/job-mine/after/file-after-1.jpg',
      );
    });
  });

  test(
    'registerJobFile sends file_type "after" + capture time, no identity',
    () async {
      final built = buildRemote((http.Request request) => <Object?>[]);

      final DateTime capturedAt = DateTime.utc(2026, 10, 7, 14, 5);
      await built.remote.registerJobFile(
        fileId: 'file-after-1',
        jobId: 'job-mine',
        fileType: JobFileType.after.name,
        storagePath: 'jobs/job-mine/after/file-after-1.jpg',
        fileName: 'finished.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: 1234,
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
      expect(body['p_file_id'], 'file-after-1');
      expect(body['p_job_id'], 'job-mine');
      expect(body['p_file_type'], 'after');
      expect(body['p_storage_path'], 'jobs/job-mine/after/file-after-1.jpg');
      expect(body['p_file_name'], 'finished.jpg');
      expect(body['p_captured_at'], capturedAt.toIso8601String());

      // Authorization facts are NEVER sent: no employee id, no role.
      expect(
        body.keys.any((String key) => key.contains('employee')),
        isFalse,
        reason: 'the RPC resolves the caller from auth.uid() itself',
      );
      expect(body.keys.any((String key) => key.contains('role')), isFalse);
    },
  );

  test(
    'getJobFilesByType filters the job_files read by file_type=after',
    () async {
      final built = buildRemote(
        (http.Request request) => <Object?>[afterRow()],
      );

      final List<JobFile> files = await built.remote.getJobFilesByType(
        'job-mine',
        'after',
      );

      expect(built.requests, hasLength(1));
      final Uri uri = built.requests.single.url;
      expect(uri.path, '/rest/v1/job_files');
      expect(uri.queryParameters['job_id'], 'eq.job-mine');
      expect(uri.queryParameters['file_type'], 'eq.after');

      // The row maps onto the shared JobFile entity — no after-specific type.
      expect(files, hasLength(1));
      expect(files.single.id, 'file-after-1');
      expect(files.single.fileType, 'after');
      expect(files.single.remotePath, 'jobs/job-mine/after/file-after-1.jpg');
      expect(
        files.single.capturedAt,
        DateTime.parse('2026-10-07T14:05:00.000Z'),
      );
      expect(files.single.syncState, JobFileSyncState.synced);
      // Cross-device restore preconditions: no local copy exists, so the
      // display name comes from the storage object and the bytes MUST be
      // routed to the Storage download path.
      expect(files.single.localPath, isNull);
      expect(files.single.fileName, 'file-after-1.jpg');
    },
  );

  test('getJobBeforePhotos still reads only before files', () async {
    final built = buildRemote((http.Request request) => <Object?>[]);

    await built.remote.getJobBeforePhotos('job-mine');

    final Uri uri = built.requests.single.url;
    expect(uri.queryParameters['file_type'], 'eq.before');
  });
}
