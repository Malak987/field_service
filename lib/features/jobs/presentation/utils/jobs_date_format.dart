import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Formats a job timestamp for the active UI locale.
///
/// Uses a `yMMMd` pattern (e.g. `4 Oct 2026` / `4. Okt. 2026` in German) —
/// short enough for list cards, precise enough for the details page.
String formatJobDate(DateTime date, BuildContext context) {
  final String locale = Localizations.localeOf(context).toString();
  return DateFormat.yMMMd(locale).format(date.toLocal());
}

/// Formats a timestamp with date and localized clock time when the stored
/// value contains time information (e.g. work start/completion timestamps).
String formatJobDateTime(DateTime date, BuildContext context) {
  final String locale = Localizations.localeOf(context).toString();
  return DateFormat.yMMMd(locale).add_jm().format(date.toLocal());
}
