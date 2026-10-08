import 'dart:convert';

import 'package:field_service/features/jobs/data/datasources/jobs_remote_data_source.dart';
import 'package:field_service/features/jobs/domain/entities/job_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Regression tests for the Create & Assign Job server contract — focused on
/// `job_number`.
///
/// Background: the real `jobs.job_number` column is GENERATED ALWAYS AS
/// IDENTITY (PostgreSQL error 428C9 refused any explicit value). The
/// corrected `create_job` RPC therefore OMITS the column and lets the
/// database assign it. These tests lock that contract at the wire level:
///
/// * the Flutter client NEVER sends a job number (not in the RPC params),
/// * the created job returned by the RPC carries the SERVER-generated
///   `job_number`, exactly as the database produced it.
void main() {
  /// A `public.jobs` row exactly as the `create_job` RPC returns it —
  /// including the identity-generated `job_number` (here: 42).
  Map<String, Object?> createdRow(int number) {
    return <String, Object?>{
      'id': 'job-new',
      'job_number': number,
      'customer_id': 'cust-1',
      'assigned_employee_id': 'emp-max',
      'job_type': 'kitchen_renovation',
      'description': 'Customer wants the kitchen renovated.',
      'status': 'assigned',
      'assigned_at': '2026-10-06T09:30:00.000Z',
      'started_at': null,
      'completed_at': null,
      'created_at': '2026-10-06T09:30:00.000Z',
      'updated_at': '2026-10-06T09:30:00.000Z',
      'expires_at': '2027-01-04T09:30:00.000Z',
      // RPC rows carry no embeds.
      'customers': null,
      'employees': null,
    };
  }

  /// Builds the real [JobsRemoteDataSourceImpl] against a captured HTTP
  /// transport, so the test asserts on the EXACT request the client sends.
  ({JobsRemoteDataSourceImpl remote, List<http.Request> requests}) buildRemote(
    int serverGeneratedNumber,
  ) {
    final List<http.Request> requests = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(<Object?>[createdRow(serverGeneratedNumber)]),
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

  test('create_job sends NO job_number — only the four form facts', () async {
    final built = buildRemote(42);

    await built.remote.createJob(
      customerId: 'cust-1',
      jobType: 'kitchen_renovation',
      description: 'Customer wants the kitchen renovated.',
      assignedEmployeeId: 'emp-max',
    );

    expect(built.requests, hasLength(1));
    final http.Request request = built.requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/rest/v1/rpc/create_job');

    final Map<String, dynamic> body =
        jsonDecode(request.body) as Map<String, dynamic>;

    // Exactly the four RPC parameters — nothing else. Most importantly:
    // NO job_number, NO timestamp. The database is the only source of both.
    expect(body.keys.toSet(), <String>{
      'p_customer_id',
      'p_job_type',
      'p_description',
      'p_assigned_employee_id',
    });
    expect(body.containsKey('job_number'), isFalse);
    expect(
      body.keys.any((String key) => key.contains('number')),
      isFalse,
      reason: 'the client must never send a job number',
    );
    expect(body['p_customer_id'], 'cust-1');
    expect(body['p_job_type'], 'kitchen_renovation');
    expect(body['p_description'], 'Customer wants the kitchen renovated.');
    expect(body['p_assigned_employee_id'], 'emp-max');
  });

  test('null description is allowed and still no number is sent', () async {
    final built = buildRemote(7);

    await built.remote.createJob(
      customerId: 'cust-1',
      jobType: 'home_renovation',
      description: null,
      assignedEmployeeId: 'emp-max',
    );

    final Map<String, dynamic> body =
        jsonDecode(built.requests.single.body) as Map<String, dynamic>;
    expect(body['p_description'], isNull);
    expect(body.containsKey('job_number'), isFalse);
  });

  test('the returned job carries the SERVER-generated job_number', () async {
    final built = buildRemote(42);

    final job = await built.remote.createJob(
      customerId: 'cust-1',
      jobType: 'kitchen_renovation',
      description: 'Renovate the kitchen.',
      assignedEmployeeId: 'emp-max',
    );

    // The identity value produced by PostgreSQL arrives untouched.
    expect(job.jobNumber, 42);
    expect(job.id, 'job-new');
    expect(job.status.value, JobStatus.assigned);
    expect(job.customerId, 'cust-1');
    expect(job.assignedEmployeeId, 'emp-max');
    expect(job.jobType, 'kitchen_renovation');
    expect(job.assignedAt, DateTime.parse('2026-10-06T09:30:00.000Z'));
  });
}
