import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Formats a customer timestamp for the active UI locale.
///
/// Same rule as the jobs date util (`yMMMd` + time, locale-aware) — kept
/// feature-local so `features/customers` does not import `features/jobs`.
String formatCustomerDate(DateTime date, BuildContext context) {
  final String locale = Localizations.localeOf(context).toString();
  return DateFormat.yMMMd(locale).add_Hm().format(date.toLocal());
}
