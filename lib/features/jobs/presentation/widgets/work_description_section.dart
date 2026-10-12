import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_cubit.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_step_empty_note.dart';
import 'package:flutter/material.dart';

/// The "Work Description" section of the Job Details page.
///
/// The technician's record of the work ACTUALLY performed — strictly
/// separate from the admin's customer request (`jobs.description`, shown in
/// the Job Information card).
///
/// The technician writes what they actually did here — in the customer's home,
/// on a phone, usually with one hand. The field is therefore deliberately roomy,
/// the save button reports the real state (busy → saving, then confirmed or
/// rejected by the cubit), and nothing is presented as saved before the cubit
/// confirms it.
///
/// Purely presentational, like the other Job Details sections:
/// * [canEdit] true (assigned technician, job `in_progress`) → multiline
///   field + Save button with busy state and inline validation errors,
/// * [canEdit] false (admins monitoring, any closed state) → read-only text
///   or a short "nothing yet" note. No write control is ever rendered.
/// All save logic lives in the cubit/repository — this widget only reports
/// taps and text.
class WorkDescriptionSection extends StatefulWidget {
  const WorkDescriptionSection({
    super.key,
    required this.initialText,
    required this.canEdit,
    required this.isSaving,
    required this.error,
    required this.onSave,
  });

  /// The currently saved work description (empty when none yet).
  final String initialText;

  /// Whether the current user may edit (assigned technician on an
  /// `in_progress` job). Everyone else gets the read-only view.
  final bool canEdit;

  /// A save is currently being submitted — disables the Save button.
  final bool isSaving;

  /// Inline validation error of the last save attempt (`null` when valid).
  final WorkDescriptionFieldError? error;

  /// Called with the raw field text when the user taps Save.
  final ValueChanged<String> onSave;

  @override
  State<WorkDescriptionSection> createState() => _WorkDescriptionSectionState();
}

class _WorkDescriptionSectionState extends State<WorkDescriptionSection> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _errorText(AppLocalizations l10n) {
    return switch (widget.error) {
      WorkDescriptionFieldError.empty => l10n.workDescriptionEmptyError,
      WorkDescriptionFieldError.tooLong => l10n.workDescriptionTooLongError(
        JobsRepository.maxWorkDescriptionLength,
      ),
      null => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l10n.workDescriptionTitle, style: context.textStyles.titleMedium),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          l10n.workDescriptionSubtitle,
          style: context.textStyles.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (widget.canEdit) ...<Widget>[
          Text(
            l10n.workDescriptionRequiredHint,
            style: context.textStyles.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const Key('work_description_field'),
            controller: _controller,
            // Room enough for a real report, and the label sits with the first
            // line instead of floating in the middle of the field.
            minLines: 4,
            maxLines: 10,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: l10n.workDescriptionHint,
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
              errorText: _errorText(l10n),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('save_work_description_button'),
              onPressed: widget.isSaving
                  ? null
                  : () => widget.onSave(_controller.text),
              icon: widget.isSaving
                  ? const SizedBox(
                      width: AppDimensions.iconSm,
                      height: AppDimensions.iconSm,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: AppDimensions.iconMd),
              label: Text(
                widget.isSaving
                    ? l10n.workDescriptionSavingLabel
                    : l10n.saveButton,
              ),
            ),
          ),
        ] else if (widget.initialText.trim().isEmpty)
          JobStepEmptyNote(
            icon: Icons.edit_note_outlined,
            title: l10n.workDescriptionNoneYet,
            message: l10n.workDescriptionRequiredHint,
          )
        else
          // What the technician recorded, in the same quiet block the rest of
          // the read-only fields use.
          Text(
            widget.initialText,
            style: context.textStyles.bodyMedium?.copyWith(
              color: context.colors.onSurface,
              height: 1.45,
            ),
          ),
      ],
    );
  }
}
