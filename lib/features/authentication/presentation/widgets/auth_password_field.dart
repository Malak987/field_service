import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:flutter/material.dart';

/// Reusable password form field with built-in show/hide visibility toggle.
///
/// Manages its own `_obscureText` state internally so toggling password
/// visibility never rebuilds the surrounding form or page.
class AuthPasswordField extends StatefulWidget {
  const AuthPasswordField({
    required this.controller,
    required this.label,
    this.hint,
    this.validator,
    this.textInputAction = TextInputAction.done,
    this.autofillHints,
    this.onFieldSubmitted,
    this.onChanged,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final TextInputAction textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _obscureText = true;

  void _toggleVisibility() {
    setState(() {
      _obscureText = !_obscureText;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      obscureText: _obscureText,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      enableSuggestions: false,
      autocorrect: false,
      validator: widget.validator,
      onFieldSubmitted: widget.onFieldSubmitted,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.lock_outline, size: AppDimensions.iconMd),
        suffixIcon: IconButton(
          onPressed: widget.enabled ? _toggleVisibility : null,
          tooltip: _obscureText
              ? l10n.showPasswordTooltip
              : l10n.hidePasswordTooltip,
          icon: Icon(
            _obscureText
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: AppDimensions.iconMd,
          ),
        ),
      ),
    );
  }
}
