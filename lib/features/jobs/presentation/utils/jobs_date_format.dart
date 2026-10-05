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
