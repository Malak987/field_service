import 'package:equatable/equatable.dart';

/// Safe, optional presentation details returned by `delete-account` for a
/// non-destructive `dry_run` request.
///
/// The account-deletion UI does not depend on a backend response schema: the
/// successful preview itself is sufficient to allow the final confirmation.
/// When the deployed function provides a concise `message`/`summary` or
/// retention detail, it is shown as supplemental server information.
class AccountDeletionPreview extends Equatable {
  const AccountDeletionPreview({this.serverMessage, this.retentionDetail});

  final String? serverMessage;
  final String? retentionDetail;

  factory AccountDeletionPreview.fromFunctionData(Object? data) {
    if (data is String && data.trim().isNotEmpty) {
      return AccountDeletionPreview(serverMessage: data.trim());
    }
    if (data is! Map) {
      return const AccountDeletionPreview();
    }

    final Map<String, Object?> values = <String, Object?>{};
    for (final MapEntry<dynamic, dynamic> entry in data.entries) {
      if (entry.key is String) {
        values[entry.key] = entry.value;
      }
    }
    return AccountDeletionPreview(
      serverMessage: _firstNonEmptyString(values, const <String>[
        'message',
        'summary',
        'preview_message',
      ]),
      retentionDetail: _firstNonEmptyString(values, const <String>[
        'retention_message',
        'retention_until',
        'retention_period',
      ]),
    );
  }

  static String? _firstNonEmptyString(
    Map<String, Object?> values,
    List<String> keys,
  ) {
    for (final String key in keys) {
      final Object? value = values[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  @override
  List<Object?> get props => <Object?>[serverMessage, retentionDetail];
}
