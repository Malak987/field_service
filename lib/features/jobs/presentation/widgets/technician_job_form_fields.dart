import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/jobs/domain/entities/new_customer_draft.dart';
import 'package:field_service/features/jobs/presentation/utils/technician_job_form_validators.dart';
import 'package:flutter/material.dart';

/// Owns the seven customer [TextEditingController]s of the technician's
/// "Create Customer & Job" form.
///
/// One holder instead of seven fields in the page: creation and disposal
/// stay in one place, and [draft] is the single place that turns raw input
/// into the domain draft (trimmed, blank → `null`).
class TechnicianCustomerFieldControllers {
  TechnicianCustomerFieldControllers();

  final TextEditingController name = TextEditingController();
  final TextEditingController phone = TextEditingController();
  final TextEditingController email = TextEditingController();
  final TextEditingController address = TextEditingController();
  final TextEditingController city = TextEditingController();
  final TextEditingController postalCode = TextEditingController();
  final TextEditingController notes = TextEditingController();

  /// The current input as a domain draft (blank optional fields → `null`).
  NewCustomerDraft get draft => NewCustomerDraft(
    name: name.text.trim(),
    address: address.text.trim(),
    phone: _nullIfBlank(phone),
    email: _nullIfBlank(email),
    city: _nullIfBlank(city),
    postalCode: _nullIfBlank(postalCode),
    notes: _nullIfBlank(notes),
  );

  /// Resets every field (used when the form switches back to a blank one).
  void clear() {
    for (final TextEditingController controller in all) {
      controller.clear();
    }
  }

  /// Every controller, for iteration.
  List<TextEditingController> get all => <TextEditingController>[
    name,
    phone,
    email,
    address,
    city,
    postalCode,
    notes,
  ];

  void dispose() {
    for (final TextEditingController controller in all) {
      controller.dispose();
    }
  }

  static String? _nullIfBlank(TextEditingController controller) {
    final String trimmed = controller.text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// The customer part of the form: exactly the columns the technician may
/// write, in the order that works on a phone (one field per line, city and
/// postal code side by side once there is room).
///
/// Must be rendered inside the caller's [Form] so `validate()` reaches these
/// fields. Pure presentation: the rules live in
/// [TechnicianJobFormValidators], the values in the caller's controllers.
class TechnicianCustomerFields extends StatelessWidget {
  const TechnicianCustomerFields({
    super.key,
    required this.controllers,
    this.enabled = true,
  });

  final TechnicianCustomerFieldControllers controllers;

  /// Disables every input while a submission is in flight.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TechnicianFormField(
          key: const Key('technician_customer_name_field'),
          controller: controllers.name,
          label: l10n.customerNameLabel,
          hint: l10n.customerNameHint,
          icon: Icons.person_outline_rounded,
          required: true,
          enabled: enabled,
          textCapitalization: TextCapitalization.words,
          validator: (String? value) =>
              TechnicianJobFormValidators.validateName(value, l10n),
        ),
        const SizedBox(height: AppSpacing.md),
        TechnicianFormField(
          key: const Key('technician_customer_phone_field'),
          controller: controllers.phone,
          label: l10n.customerPhoneLabel,
          hint: l10n.customerPhoneHint,
          icon: Icons.phone_outlined,
          enabled: enabled,
          keyboardType: TextInputType.phone,
          validator: (String? value) =>
              TechnicianJobFormValidators.validateOptionalPhone(value, l10n),
        ),
        const SizedBox(height: AppSpacing.md),
        TechnicianFormField(
          key: const Key('technician_customer_email_field'),
          controller: controllers.email,
          label: l10n.customerEmailLabel,
          hint: l10n.customerEmailHint,
          icon: Icons.mail_outline_rounded,
          enabled: enabled,
          keyboardType: TextInputType.emailAddress,
          validator: (String? value) =>
              TechnicianJobFormValidators.validateOptionalEmail(value, l10n),
        ),
        const SizedBox(height: AppSpacing.md),
        TechnicianFormField(
          key: const Key('technician_customer_address_field'),
          controller: controllers.address,
          label: l10n.customerAddressLabel,
          hint: l10n.customerAddressHint,
          icon: Icons.place_outlined,
          required: true,
          enabled: enabled,
          textCapitalization: TextCapitalization.sentences,
          validator: (String? value) =>
              TechnicianJobFormValidators.validateAddress(value, l10n),
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget city = TechnicianFormField(
              key: const Key('technician_customer_city_field'),
              controller: controllers.city,
              label: l10n.customerCityLabel,
              hint: l10n.customerCityHint,
              icon: Icons.location_city_outlined,
              enabled: enabled,
              textCapitalization: TextCapitalization.words,
              validator: (String? value) =>
                  TechnicianJobFormValidators.validateOptionalCity(
                    value,
                    l10n,
                  ),
            );
            final Widget postalCode = TechnicianFormField(
              key: const Key('technician_customer_postal_code_field'),
              controller: controllers.postalCode,
              label: l10n.customerPostalCodeLabel,
              hint: l10n.customerPostalCodeHint,
              icon: Icons.markunread_mailbox_outlined,
              enabled: enabled,
              keyboardType: TextInputType.streetAddress,
              validator: (String? value) =>
                  TechnicianJobFormValidators.validateOptionalPostalCode(
                    value,
                    l10n,
                  ),
            );

            if (constraints.maxWidth < 420) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  city,
                  const SizedBox(height: AppSpacing.md),
                  postalCode,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: city),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: postalCode),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        TechnicianFormField(
          key: const Key('technician_customer_notes_field'),
          controller: controllers.notes,
          label: l10n.customerNotesLabel,
          hint: l10n.customerNotesHint,
          icon: Icons.notes_outlined,
          enabled: enabled,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          textCapitalization: TextCapitalization.sentences,
          minLines: 2,
          maxLines: 4,
          validator: (String? value) =>
              TechnicianJobFormValidators.validateOptionalNotes(value, l10n),
        ),
      ],
    );
  }
}

/// One labelled text field of the technician forms.
///
/// The single place where this form's field decoration is decided, so every
/// field looks and behaves the same on Android and iOS.
class TechnicianFormField extends StatelessWidget {
  const TechnicianFormField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.required = false,
    this.enabled = true,
    this.readOnly = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.minLines = 1,
    this.maxLines = 1,
    this.validator,
    this.helperText,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final bool required;
  final bool enabled;
  final bool readOnly;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final int minLines;
  final int maxLines;
  final FormFieldValidator<String>? validator;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      readOnly: readOnly,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      minLines: minLines,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        helperText: helperText,
        prefixIcon: icon == null ? null : Icon(icon),
      ),
    );
  }
}

/// A numbered section heading, matching the visual language of the admin
/// Create Job screen (numbered badge + localized title).
class TechnicianJobFormSection extends StatelessWidget {
  const TechnicianJobFormSection({
    super.key,
    required this.number,
    required this.title,
    required this.child,
  });

  final String number;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Text(
                number,
                style: context.textStyles.labelLarge?.copyWith(
                  color: context.colors.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                title,
                style: context.textStyles.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    );
  }
}
