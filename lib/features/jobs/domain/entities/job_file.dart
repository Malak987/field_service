import 'package:equatable/equatable.dart';

/// Local sync lifecycle of a job file, using ONLY the states the existing
/// sync architecture knows (`job_files.sync_status` + the sync queue).
enum JobFileSyncState {
  /// The file is stored locally and its upload is queued / awaiting retry.
  pending,

  /// The backend confirmed the upload; [JobFile.remotePath] is set.
  synced,
}

/// Domain entity for a file attached to a job (this phase: before photos).
///
/// Identity: [id] is the stable, client-generated uuid created at capture
/// time — the sync queue, the local row, the remote `job_files` row and the
/// Storage object path all share it, which is what makes retries idempotent.
///
/// Timestamps: [capturedAt] is the ORIGINAL capture time, recorded
/// automatically when the photo is taken. It is preserved through the whole
/// sync path and is never replaced by the upload time.
class JobFile extends Equatable {
  const JobFile({
    required this.id,
    required this.jobId,
    required this.fileType,
    required this.fileName,
    required this.capturedAt,
    this.mimeType,
    this.sizeBytes,
    this.localPath,
    this.remotePath,
    this.syncState = JobFileSyncState.pending,
  });

  /// Stable file id (uuid), generated on the device at capture time.
  final String id;

  /// The job this file belongs to (`jobs.id`).
  final String jobId;

  /// What the file is: `before`, `after`, `signature`, `document`.
  final String fileType;

  /// Original file name (display only — never the storage identity).
  final String fileName;

  /// MIME type, when known (e.g. `image/jpeg`).
  final String? mimeType;

  /// Size in bytes, when known.
  final int? sizeBytes;

  /// When the photo was captured — automatic, never user-entered, and never
  /// overwritten by a later upload time.
  final DateTime capturedAt;

  /// Path of the local copy, relative to the app-owned storage root. `null`
  /// for files that exist only on the backend (captured on another device).
  final String? localPath;

  /// Supabase Storage object path, once the upload is confirmed. `null`
  /// while the upload is still queued/pending.
  final String? remotePath;

  /// Where the file currently lives (sync architecture states only).
  final JobFileSyncState syncState;

  /// Whether this file exists locally (bytes readable from device storage).
  bool get hasLocalCopy => localPath != null;

  JobFile copyWith({
    String? fileType,
    String? fileName,
    String? mimeType,
    int? sizeBytes,
    DateTime? capturedAt,
    String? localPath,
    String? remotePath,
    JobFileSyncState? syncState,
    bool clearLocalPath = false,
    bool clearRemotePath = false,
  }) {
    return JobFile(
      id: id,
      jobId: jobId,
      fileType: fileType ?? this.fileType,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      capturedAt: capturedAt ?? this.capturedAt,
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
      remotePath: clearRemotePath ? null : (remotePath ?? this.remotePath),
      syncState: syncState ?? this.syncState,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    id,
    jobId,
    fileType,
    fileName,
    mimeType,
    sizeBytes,
    capturedAt,
    localPath,
    remotePath,
    syncState,
  ];
}
