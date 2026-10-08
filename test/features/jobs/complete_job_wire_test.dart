import 'dart:convert';

import 'package:field_service/features/jobs/data/datasources/jobs_remote_data_source.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wire-level contract tests of the Complete Job data path.
///
/// The completion RPC is the FINAL workflow step and accepts NOTHING but
/// the job id: no employee id, no `completed_at`, no `has_*` flags. Server
/// refusals travel back as stable error codes that the data source maps
/// onto the typed [CompletionRejectReason] so the UI can explain WHY.
void main() {
  Map<String, Object?> completedJobRow() {
    return <String, Object?>{
      'id': 'job-mine',
      'job_number': 101,
      'customer_id': 'cust-1',
      'assigned_employee_id': 'emp-tech-1',
      'job_type': 'kitchen_renovation',
      'description': 'Fix the sink.',
      'work_description': 'Replaced the sink.',
      'status': 'completed',
      'assigned_at': '2026-09-01T08:00:00.000Z',
      'started_at': '2026-10-06T09:30:00.000Z',
      'completed_at': '2026-10-07T16:15:00.000Z',
      'created_at': '2026-09-01T08:00:00.000Z',
      'updated_at': '2026-10-07T16:15:00.000Z',
      'expires_at': '2026-12-01T00:00:00.000Z',
      'customers': null,
      'employees': null,
    };
  }

  ({JobsRemoteDataSourceImpl remote, List<http.Request> requests}) buildRemote(
    Object? Function(http.Request request) respond,
  ) {
    final List<http.Request> requests = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      requests.add(request);
      final Object? body = respond(request);
      if (body is http.Response) {
        return body;
      }
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
    return (remote: JobsRemoteDataSourceImpl(supabase), requests: requests);
  }

  /// Builds a PostgREST-style error response for [code].
  http.Response postgrestError(
    http.Request request,
    String code,
    String message,
  ) {
    return http.Response(
      jsonEncode(<String, Object?>{
        'message': message,
        'code': code,
        'details': '00000000-0000-0000-0000-000000000000',
        'hint': null,
      }),
      400,
      headers: <String, String>{'content-type': 'application/json'},
      request: request,
    );
  }

  test('completeJob sends the complete_job RPC with ONLY the job id', () async {
    final built = buildRemote(
      (http.Request request) => <Object?>[completedJobRow()],
    );

    final Job job = await built.remote.completeJob('job-mine');

    expect(built.requests, hasLength(1));
    final http.Request request = built.requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/rest/v1/rpc/complete_job');

    final Map<String, dynamic> body =
        jsonDecode(request.body) as Map<String, dynamic>;
    expect(body, <String, dynamic>{'p_job_id': 'job-mine'});

    // Authorization and timing facts are NEVER sent: no employee id, no
    // timestamp, no has_* flags — the server decides all of it itself.
    expect(
      body.keys.any(
        (String key) =>
            key.contains('employee') ||
            key.contains('completed') ||
            key.contains('has_'),
      ),
      isFalse,
    );

    // The authoritative row comes back mapped — completed, server-stamped.
    expect(job.id, 'job-mine');
    expect(job.status.value, 'completed');
    expect(job.completedAt, DateTime.parse('2026-10-07T16:15:00.000Z'));
  });

  test('server refusals map onto the typed completion reasons', () async {
    // (server code, server message) → expected reason
    final List<(String, CompletionRejectReason)> cases =
        <(String, CompletionRejectReason)>[
          ('F0001', CompletionRejectReason.missingBeforePhoto),
          ('F0002', CompletionRejectReason.missingWorkDescription),
          ('F0003', CompletionRejectReason.missingAfterPhoto),
          ('F0004', CompletionRejectReason.missingSignature),
          ('F0005', CompletionRejectReason.notAssigned),
          ('F0006', CompletionRejectReason.invalidStatus),
          ('F0007', CompletionRejectReason.unauthorized),
          // No auth session / no active employee — also unauthorized.
          ('28000', CompletionRejectReason.unauthorized),
          // Anything unrecognized stays `unknown` — never silent success.
          ('P0002', CompletionRejectReason.unknown),
        ];

    for (final (String code, CompletionRejectReason expected) in cases) {
      final built = buildRemote(
        (http.Request request) =>
            postgrestError(request, code, 'Server refusal $code.'),
      );

      await expectLater(
        () => built.remote.completeJob('job-mine'),
        throwsA(
          isA<JobCompletionRejectedException>().having(
            (JobCompletionRejectedException e) => e.reason,
            'reason',
            expected,
          ),
        ),
        reason: 'code $code must map to $expected',
      );
    }
  });

  test('the refusal keeps the server message for diagnostics', () async {
    final built = buildRemote(
      (http.Request request) => postgrestError(
        request,
        'F0004',
        'A customer signature is required to complete this job.',
      ),
    );

    try {
      await built.remote.completeJob('job-mine');
      fail('expected JobCompletionRejectedException');
    } on JobCompletionRejectedException catch (error) {
      expect(error.reason, CompletionRejectReason.missingSignature);
      expect(
        error.serverMessage,
        'A customer signature is required to complete this job.',
      );
    }
  });
}
