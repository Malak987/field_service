import 'dart:typed_data';

import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/jobs/domain/entities/job_file.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_cubit.dart';
import 'package:field_service/features/jobs/presentation/widgets/before_photo_tile.dart';
import 'package:field_service/features/jobs/presentation/widgets/signature_pad.dart';
import 'package:flutter/material.dart';

/// The "Customer Signature" section of the Job Details page.
///
/// Purely presentational, same contract pattern as the photo sections:
/// * no signature yet + [canCapture] (assigned technician, job
///   `in_progress`) → touch drawing pad + **Clear** + **Save Signature**
///   with busy state and the inline "signature required" error,
/// * a captured signature → its preview with the existing sync badge
///   (pending / synced / failed) — for the technician AND the monitoring
///   admin, read-only. The capturing technician additionally gets a
///   **Replace Signature** entry point (the workflow allows another capture
///   while the job is `in_progress`; the server re-validates every rule),
/// * nothing captured and no capture permission → a short "nothing yet"
///   note. No write control is ever rendered for admins or closed jobs.
/// All capture logic lives in the cubit/repository — this widget only
/// reports taps and the rendered PNG bytes.
///
/// [onDrawingChanged] is forwarded to the pad so the hosting page can
/// freeze its scrolling while the customer draws.
class SignatureSection extends StatefulWidget {
  const SignatureSection({
    super.key,
    required this.signature,
    required this.failedIds,
    required this.canCapture,
    required this.isCapturing,
    required this.error,
    required this.onCapture,
    required this.onRetry,
    required this.loadBytes,
    this.onDrawingChanged,
  });

  /// The latest captured signature file, or `null` when none exists yet.
  final JobFile? signature;

  /// Ids of signature files whose upload is `failed` in the sync queue.
  final Set<String> failedIds;

  /// Whether the signature may be captured (assigned technician on an
  /// `in_progress` job). Everyone else gets the read-only view.
  final bool canCapture;

  /// A capture is currently being persisted locally — disables the buttons.
  final bool isCapturing;

  /// Inline validation error of the last capture attempt (`null` when
  /// valid).
  final SignatureFieldError? error;

  /// Called with the rendered PNG bytes when the customer confirms the
  /// drawing. An EMPTY drawing is reported as an empty byte list so the
  /// cubit can publish the inline validation error.
  final Future<void> Function(Uint8List pngBytes) onCapture;

  /// Called when the user taps **Retry** while the upload has failed.
  final VoidCallback onRetry;

  /// Resolves the displayable bytes of the stored signature (lazy loading).
  final Future<Uint8List?> Function(JobFile file) loadBytes;

  /// Forwarded to the [SignaturePad]: `true` while a finger draws, `false`
  /// once it lifts — the page freezes its scrolling in that window.
  final ValueChanged<bool>? onDrawingChanged;

  @override
  State<SignatureSection> createState() => _SignatureSectionState();
}

class _SignatureSectionState extends State<SignatureSection> {
  final GlobalKey<SignaturePadState> _padKey = GlobalKey<SignaturePadState>();

  /// Whether the technician chose to REPLACE an already captured signature:
  /// the pad is shown again in place of the preview until they save a new
  /// drawing or cancel back to the preview.
  bool _replacing = false;

  @override
  void didUpdateWidget(SignatureSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A freshly captured signature (or losing capture permission) always
    // returns the section to the preview/read-only presentation.
    if (widget.signature?.id != oldWidget.signature?.id || !widget.canCapture) {
      _replacing = false;
    }
  }

  Future<void> _confirm() async {
    final SignaturePadState? pad = _padKey.currentState;
    if (pad == null) {
      return;
    }
    // An empty drawing is reported with empty bytes — the cubit refuses it
    // and publishes the inline error; nothing enters storage or the queue.
    final Uint8List bytes = pad.isEmpty ? Uint8List(0) : await pad.exportPng();
    await widget.onCapture(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final JobFile? signature = widget.signature;
    final bool showPad = widget.canCapture && (signature == null || _replacing);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.customerSignatureTitle,
          style: context.textStyles.titleMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        if (signature != null && !_replacing) ...<Widget>[
          if (widget.failedIds.contains(signature.id)) ...<Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.cloud_off_rounded, size: AppDimensions.iconMd),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(l10n.uploadFailedLabel)),
                TextButton(
                  key: const Key('retry_signature_button'),
                  onPressed: widget.onRetry,
                  child: Text(l10n.retryButton),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          // The captured signature, displayed with the same tile/badge
          // patterns as the photos (pending sync / synced / failed).
          SizedBox(
            height: 200,
            width: double.infinity,
            child: BeforePhotoTile(
              key: Key('signature_tile_${signature.id}'),
              file: signature,
              isFailed: widget.failedIds.contains(signature.id),
              loadBytes: widget.loadBytes,
            ),
          ),
          if (widget.canCapture) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            // The workflow allows another capture while the job is still
            // `in_progress` (the server re-checks every rule); a new
            // signature is a NEW file id — the preview always shows the
            // latest one.
            TextButton.icon(
              key: const Key('replace_signature_button'),
              onPressed: widget.isCapturing
                  ? null
                  : () => setState(() => _replacing = true),
              icon: const Icon(Icons.edit_outlined, size: AppDimensions.iconSm),
              label: Text(l10n.replaceSignatureButton),
            ),
          ],
        ] else if (showPad) ...<Widget>[
          Text(
            l10n.signatureHelper,
            style: context.textStyles.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SignaturePad(
            key: _padKey,
            // Taller than the standalone default: a comfortable signing
            // area for a finger, not a stylus.
            height: 260,
            onDrawingChanged: widget.onDrawingChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  OutlinedButton.icon(
                    key: const Key('clear_signature_button'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: widget.isCapturing
                        ? null
                        : () => _padKey.currentState?.clear(),
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: AppDimensions.iconMd,
                    ),
                    label: Text(l10n.clearButton),
                  ),
                  if (_replacing && signature != null)
                    TextButton(
                      key: const Key('cancel_replace_signature_button'),
                      onPressed: widget.isCapturing
                          ? null
                          : () => setState(() => _replacing = false),
                      child: Text(l10n.cancelButton),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.icon(
                key: const Key('save_signature_button'),
                onPressed: widget.isCapturing ? null : _confirm,
                icon: widget.isCapturing
                    ? const SizedBox(
                        width: AppDimensions.iconSm,
                        height: AppDimensions.iconSm,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.draw_rounded,
                        size: AppDimensions.iconMd,
                      ),
                label: Text(
                  widget.isCapturing
                      ? l10n.uploadingLabel
                      : l10n.saveSignatureButton,
                ),
              ),
            ],
          ),
          if (widget.error == SignatureFieldError.empty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.signatureRequiredError,
              style: context.textStyles.bodyMedium?.copyWith(
                color: AppColors.error,
              ),
            ),
          ],
        ] else
          Text(l10n.noSignatureYet, style: context.textStyles.bodyMedium),
      ],
    );
  }
}
