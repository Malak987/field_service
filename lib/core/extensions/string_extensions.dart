/// Small string helpers shared by every feature.
///
/// Kept dependency-free and free of business rules: anything that only applies
/// to one feature belongs in that feature instead.
extension StringX on String {
  /// Whether the string is empty or contains only whitespace.
  bool get isBlank => trim().isEmpty;

  /// Whether the string contains at least one non-whitespace character.
  ///
  /// Useful for form validation, where `'   '` must be treated as "not filled
  /// in" and never sent to the backend.
  bool get isNotBlank => !isBlank;

  /// Returns `null` when the string is blank.
  ///
  /// Handy for optional fields and for payloads that must omit empty values
  /// instead of sending `""`.
  String? get nullIfBlank => isBlank ? null : this;

  /// The string with its first character upper-cased.
  String get capitalized {
    if (isEmpty) {
      return this;
    }
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
