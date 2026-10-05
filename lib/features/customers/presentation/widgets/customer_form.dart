import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/customers/presentation/utils/customer_form_validators.dart';
import 'package:flutter/material.dart';

/// What a submitted customer form produced (raw strings, trimmed; blank
/// optional fields arrive as `null`).
class CustomerFormData {
  const CustomerFormData({
    required this.name,
    required this.address,
    this.phone,
    this.email,
    this.city,
    this.postalCode,
    this.notes,
  });

  final String name;
  final String address;
  final String? phone;
  final String? email;
  final String? city;
  final String? postalCode;
  final String? notes;
}

/// The single reusable customer form (create **and** edit).
///
/// All form logic — controllers, validation wiring, pre-filling and
/// submission shaping — lives here; the create/edit pages stay thin wrappers
/// around it plus their Cubit calls. The rules themselves are centralized in
/// [CustomerFormValidators] so both pages (and any future picker dialog)
/// validate exactly the same way.
class CustomerForm extends StatefulWidget {
  const CustomerForm({
    super.key,
    this.initial,
    required this.onSubmit,
    required this.submitLabel,
    this.isBusy = false,
    this.onCancel,
  });

  /// Existing customer to pre-fill (edit mode); `null` for a blank create.
  final Customer? initial;

  /// Called once with the validated values.
  final ValueChanged<CustomerFormData> onSubmit;

  /// Localized label of the submit button ("Save").
  final String submitLabel;

  /// Disables inputs and shows a spinner on the button while saving.
  final bool isBusy;

  /// Optional "Cancel" action (rendered as a text button under the form).
  final VoidCallback? onCancel;

  @override
  State<CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<CustomerForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _postalCode;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    final Customer? initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _phone = TextEditingController(text: initial?.phone ?? '');
    _email = TextEditingController(text: initial?.email ?? '');
    _address = TextEditingController(text: initial?.address ?? '');
    _city = TextEditingController(text: initial?.city ?? '');
    _postalCode = TextEditingController(text: initial?.postalCode ?? '');
    _notes = TextEditingController(text: initial?.notes ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _city.dispose();
    _postalCode.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    widget.onSubmit(
      CustomerFormData(
        name: _name.text.trim(),
        address: _address.text.trim(),
        phone: _trimmedOrNull(_phone),
        email: _trimmedOrNull(_email),
        city: _trimmedOrNull(_city),
        postalCode: _trimmedOrNull(_postalCode),
        notes: _trimmedOrNull(_notes),
      ),
    );
  }

  String? _trimmedOrNull(TextEditingController controller) {
    final String trimmed = controller.text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _field(
              controller: _name,
              label: l10n.customerNameLabel,
              textCapitalization: TextCapitalization.words,
              validator: (String? value) =>
                  CustomerFormValidators.validateRequired(value, l10n),
            ),
            const SizedBox(height: AppSpacing.lg),
            _field(
              controller: _phone,
              label: l10n.customerPhoneLabel,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: AppSpacing.lg),
            _field(
              controller: _email,
              label: l10n.customerEmailLabel,
              keyboardType: TextInputType.emailAddress,
              validator: (String? value) =>
                  CustomerFormValidators.validateOptionalEmail(value, l10n),
            ),
            const SizedBox(height: AppSpacing.lg),
            _field(
              controller: _address,
              label: l10n.customerAddressLabel,
              textCapitalization: TextCapitalization.sentences,
              validator: (String? value) =>
                  CustomerFormValidators.validateRequired(value, l10n),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _field(
                    controller: _city,
                    label: l10n.customerCityLabel,
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _field(
                    controller: _postalCode,
                    label: l10n.customerPostalCodeLabel,
                    keyboardType: TextInputType.streetAddress,
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _field(
              controller: _notes,
              label: l10n.customerNotesLabel,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              minLines: 1,
            ),
            const SizedBox(height: AppSpacing.xxl),
            FilledButton(
              onPressed: widget.isBusy ? null : _submit,
              child: widget.isBusy
                  ? SizedBox(
                      height: AppDimensions.iconSm,
                      width: AppDimensions.iconSm,
                      child: const CircularProgressIndicator(
                        strokeWidth: AppDimensions.spinnerStrokeWidth,
                      ),
                    )
                  : Text(l10n.saveButton),
            ),
            if (widget.onCancel != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: widget.isBusy ? null : widget.onCancel,
                child: Text(l10n.cancelButton),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Declarative per-field builder so the decoration/enable/validation
  /// boilerplate exists exactly once.
  Widget _field({
    required TextEditingController controller,
    required String label,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.next,
    TextCapitalization textCapitalization = TextCapitalization.none,
    int maxLines = 1,
    int minLines = 1,
    FormFieldValidator<String>? validator,
  }) {
    return TextFormField(
      controller: controller,
      enabled: !widget.isBusy,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      maxLines: maxLines,
      minLines: minLines,
      validator: validator,
      decoration: InputDecoration(labelText: label),
    );
  }
}
