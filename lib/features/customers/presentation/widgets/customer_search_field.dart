import 'dart:async';

import 'package:field_service/core/constants/app_constants.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Debounced search box for the customers list.
///
/// Filtering itself runs against the local list in memory — this widget only
/// captures the query and throttles re-renders with
/// [AppConstants.customerSearchDebounce]. Works identically offline.
class CustomerSearchField extends StatefulWidget {
  const CustomerSearchField({super.key, required this.onQueryChanged});

  /// Called with the (already trimmed) query after the debounce window.
  final ValueChanged<String> onQueryChanged;

  @override
  State<CustomerSearchField> createState() => _CustomerSearchFieldState();
}

class _CustomerSearchFieldState extends State<CustomerSearchField> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // Rebuild for the suffix clear button; the query itself is debounced.
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(AppConstants.customerSearchDebounce, () {
      if (mounted) {
        widget.onQueryChanged(value.trim());
      }
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    widget.onQueryChanged('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return TextField(
      controller: _controller,
      onChanged: _onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        hintText: l10n.searchCustomersHint,
        prefixIcon: const Icon(Icons.search, size: AppDimensions.iconMd),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: AppDimensions.iconSm),
                onPressed: _clear,
              ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
      ),
    );
  }
}
