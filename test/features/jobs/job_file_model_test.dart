import 'package:field_service/features/jobs/data/models/job_file_model.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the "files disappear after data reset / on another
/// device" bug.
///
/// The live `public.job_files` schema persists ONLY:
///   id, job_id, file_type, storage_path, created_at, captured_at.
/// There are NO employee_id/file_name/mime_type/size_bytes columns.
///
/// The old `fromRemote` hard-cast `row['file_name'] as String`; PostgREST
/// returns rows without that key, so EVERY remote row threw a TypeError —
/// silently swallowed by the watch merge — and backend-registered files
/// never reached the UI. These tests pin the mapping to the live schema.
void main() {
  Map<String, Object?> liveRow({
    String id = 'file-before-1',
    String fileType = 'before',
  }) {
    return <String, Object?>{
      'id': id,
      'job_id': 'job-1',
      'file_type': fileType,
      'storage_path': 'jobs/job-1/$fileType/$id.webp',
      'captured_at': '2026-10-07T14:05:00.000Z',
      'created_at': '2026-10-07T14:05:30.000Z',
    };
  }

  test('maps a live-schema remote row (no file_name/mime/size columns)', () {
    final JobFile file = JobFileModel.fromRemote(liveRow());

    expect(file.id, 'file-before-1');
    expect(file.jobId, 'job-1');
    expect(file.fileType, 'before');
    expect(file.remotePath, 'jobs/job-1/before/file-before-1.webp');
    expect(file.capturedAt, DateTime.parse('2026-10-07T14:05:00.000Z'));
    // Backend-confirmed rows are synced; nothing is queued for them.
    expect(file.syncState, JobFileSyncState.synced);
  });

  test('a remote row has no local copy and derives its display name', () {
    final JobFile file = JobFileModel.fromRemote(
      liveRow(id: 'sig-9', fileType: 'signature'),
    );

    // localPath == null is the exact precondition that routes
    // `readPhotoBytes` to the Supabase Storage download — the cross-device
    // and data-reset restore path. Never "local file missing → nothing".
    expect(file.localPath, isNull);
    expect(file.fileName, 'sig-9.webp');
    // Absent optional metadata stays absent instead of crashing.
    expect(file.mimeType, isNull);
    expect(file.sizeBytes, isNull);
  });

  test('tolerates legacy rows that still carry optional metadata keys', () {
    final Map<String, Object?> row = liveRow()
      ..addAll(<String, Object?>{
        'mime_type': 'image/webp',
        'size_bytes': 4321,
      });

    final JobFile file = JobFileModel.fromRemote(row);

    expect(file.mimeType, 'image/webp');
    expect(file.sizeBytes, 4321);
  });
}
