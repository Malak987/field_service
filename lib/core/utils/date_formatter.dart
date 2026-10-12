import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Formats a date as a full, readable day for the active UI locale
/// (e.g. `Monday, 12 October 2026` / `Montag, 12. Oktober 2026`).
///
/// Used for the dashboard header, where the day matters more than the precise
/// time. Job timestamps keep their own short formatters in the jobs feature —
/// this one exists so a screen never reaches for `DateFormat` directly and
/// hard-codes a locale.
String formatFullDate(DateTime date, BuildContext context) {
  final String locale = Localizations.localeOf(context).toString();
  return DateFormat.yMMMMEEEEd(locale).format(date.toLocal());
}
