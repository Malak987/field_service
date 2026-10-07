/// Value object for the business job category (`jobs.job_type`).
///
/// The business has EXACTLY two job categories. The database column stores
/// the stable backend value; the UI displays localized labels (see
/// `JobLabelMapper`). Legacy free-text values were migrated to these two
/// values and a CHECK constraint locks the set at the database level, so
/// anything outside [supportedValues] can only ever reach the app from a
/// row created before the migration ran on that project — it round-trips
/// safely and is displayed raw, never as a supported category.
class JobCategory {
  const JobCategory(this.value);

  /// The raw stable value stored in `jobs.job_type`.
  final String value;

  // --- The two supported categories -----------------------------------------

  /// Home Renovation (Hausrenovierung).
  static const String homeRenovation = 'home_renovation';

  /// Kitchen Renovation (Küchenrenovierung).
  static const String kitchenRenovation = 'kitchen_renovation';

  /// Every category the business supports — the single source of truth for
  /// selectors, validation and tests. Nothing else exists at this stage.
  static const List<String> supportedValues = <String>[
    homeRenovation,
    kitchenRenovation,
  ];

  /// Whether [value] is one of the two supported categories.
  static bool isSupported(String? value) =>
      value != null && supportedValues.contains(value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JobCategory && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
