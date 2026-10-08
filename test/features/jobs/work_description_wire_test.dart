import 'dart:convert';

import 'package:field_service/features/jobs/data/datasources/jobs_remote_data_source.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wire-level contract test of the `save_work_description` RPC call.
///
/// The client sends EXACTLY two parameters — the job id and the text.
/// It never sends an employee id (the RPC resolves the caller from
/// `auth.uid()`) and never sends a timestamp (the RPC stamps `now()`
/// itself). The response is the updated job row, including the stored
/// `work_description`.
void main() {
  /// A `public.jobs` row exactly as `save_work_description` returns it
  /// (RETURN SETOF jobs, exactly one row).
  Map<String, Object?> updatedRow(String workDescription) {
    return <String, Object?>{
      'id': 'job-mine',
      'job_number': 101,
      'customer_id': 'cust-1',
      'assigned_employee_id': 'emp-me',
      'job_type': 'kitchen_renovation',
      'description': 'Customer wants the kitchen renovated.',
      'work_description': workDescription,
      'status': 'in_progress',
      'assigned_at': '2026-10-01T08:00:00.000Z',
      'started_at': '2026-10-06T09:30:00.000Z',
      'completed_at': null,
      'created_at': '2026-10-01T08:00:00.000Z',
      'updated_at': '2026-10-06T10:15:00.000Z',
      'expires_at': '2027-01-04T08:00:00.000Z',
      'customers': null,
      'employees': null,
    };
  }

  /// Builds the REAL [JobsRemoteDataSourceImpl] against a captured HTTP
  /// transport so the test can assert on the exact request on the wire.
  ({JobsRemoteDataSourceImpl remote, List<http.Request> requests}) buildRemote(
    String storedText,
  ) {
    final List<http.Request> requests = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(<Object?>[updatedRow(storedText)]),
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
    return (remote: JobsRemoteDataSourceImpl(supabase), requests: requests);
  }

  test(
    'sends ONLY the job id and the text — no identity, no timestamp',
    () async {
      final built = buildRemote('Replaced the sink and sealed all joints.');

      await built.remote.saveWorkDescription(
        jobId: 'job-mine',
        workDescription: 'Replaced the sink and sealed all joints.',
      );

      expect(built.requests, hasLength(1));
      final http.Request request = built.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/v1/rpc/save_work_description');

      final Map<String, dynamic> body =
          jsonDecode(request.body) as Map<String, dynamic>;

      // Exactly the two RPC parameters — nothing else.
      expect(body.keys.toSet(), <String>{'p_job_id', 'p_work_description'});
      expect(body['p_job_id'], 'job-mine');
      expect(
        body['p_work_description'],
        'Replaced the sink and sealed all joints.',
      );

      // The caller's identity and any time value are resolved server-side.
      expect(
        body.keys.any((String key) => key.contains('employee')),
        isFalse,
        reason: 'the RPC resolves the caller from auth.uid() itself',
      );
      expect(
        body.keys.any(
          (String key) => key.contains('at') || key.contains('time'),
        ),
        isFalse,
        reason: 'the database stamps now() itself; the client sends no time',
      );
    },
  );

  test('the returned row is mapped onto the job entity', () async {
    final built = buildRemote('Replaced the sink and sealed all joints.');

    final job = await built.remote.saveWorkDescription(
      jobId: 'job-mine',
      workDescription: 'Replaced the sink and sealed all joints.',
    );

    expect(job.id, 'job-mine');
    expect(job.status.value, JobStatus.inProgress);
    expect(job.workDescription, 'Replaced the sink and sealed all joints.');
    // The admin's customer request round-trips untouched.
    expect(job.description, 'Customer wants the kitchen renovated.');
  });

  test('an empty result set is a hard failure, not a silent success', () async {
    final List<http.Request> requests = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(<Object?>[]),
        200,
        headers: <String, String>{'content-type': 'application/json'},
        request: request,
      );
    });
    final SupabaseClient supabase = SupabaseClient(
      'https://project.supabase.co',
      'test-anon-key',
      httpClient: client,
    );
    final JobsRemoteDataSourceImpl remote = JobsRemoteDataSourceImpl(supabase);

    await expectLater(
      () => remote.saveWorkDescription(jobId: 'job-mine', workDescription: 'x'),
      throwsStateError,
    );
  });

  test('the job list query selects the work_description column', () async {
    final List<http.Request> requests = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(<Object?>[updatedRow('Some work.')]),
        200,
        headers: <String, String>{'content-type': 'application/json'},
        request: request,
      );
    });
    final SupabaseClient supabase = SupabaseClient(
      'https://project.supabase.co',
      'test-anon-key',
      httpClient: client,
    );
    final JobsRemoteDataSourceImpl remote = JobsRemoteDataSourceImpl(supabase);

    final jobs = await remote.getJobs();

    expect(jobs.single.workDescription, 'Some work.');
    final Uri uri = requests.single.url;
    expect(uri.queryParameters['select'], contains('work_description'));
  });
}
