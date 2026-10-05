/// Value object wrapping the raw `jobs.status` text column.
///
/// The backend stores `status` as free `text` (NOT a PostgreSQL enum), so this
/// type is deliberately a flexible string wrapper rather than a closed Dart
/// enum. A small set of *known* values is declared for presentation (badge
/// colour / localized label); any value outside that set still round-trips
/// safely and falls back to displaying the raw string.
class JobStatus {
  const JobStatus(this.value);

  /// The raw value stored in `jobs.status`.
  final String value;

  // --- Known values (presentation helpers). Not exhaustive by design. ------

  /// Default status when a job is created.
  static const String assigned = 'assigned';

  /// The technician has started on-site work (`started_at` set).
  static const String started = 'started';

  /// Alias some backends use for an in-progress job.
  static const String inProgress = 'in_progress';

  /// The job is finished (`completed_at` set).
  static const String completed = 'completed';

  /// The job was cancelled.
  static const String cancelled = 'cancelled';

  /// The set of values we have a dedicated localized label + colour for.
  static const Set<String> knownValues = <String>{
    assigned,
    started,
    inProgress,
    completed,
    cancelled,
  };

  /// Whether [value] is one of the known values.
  bool get isKnown => knownValues.contains(value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JobStatus && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
