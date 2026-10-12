import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';
import 'package:field_service/features/jobs/domain/entities/job_customer_info.dart';
import 'package:field_service/features/jobs/presentation/cubit/jobs_state.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:field_service/features/jobs/presentation/utils/jobs_date_format.dart';
import 'package:field_service/features/jobs/presentation/widgets/job_detail_field.dart';
import 'package:flutter/material.dart';

/// The job's own record: number, type, status, assignee and the lifecycle
/// timestamps that exist in `public.jobs`.
///
/// Empty values are omitted rather than shown as a dash, so the block stays
/// short on a phone and the eye is not led to blanks.
class JobDetailsFields extends StatelessWidget {
  const JobDetailsFields({
    super.key,
    required this.job,
    required this.mapper,
  });

  final Job job;
  final JobLabelMapper mapper;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final List<(String, String)> values = <(String, String)>[];

    void add(String label, String? value) {
      if (value == null || value.trim().isEmpty) return;
      values.add((label, value.trim()));
    }

    add(l10n.jobNumberLabel, '#${job.jobNumber}');
    add(l10n.jobTypeLabel, mapper.jobTypeLabel(job.jobType));
    add(l10n.statusLabel, mapper.statusLabel(job.status));
    add(l10n.assignedTechnicianLabel, job.assignedEmployeeName);
    add(
      l10n.assignedDateLabel,
      job.assignedAt == null ? null : formatJobDate(job.assignedAt!, context),
    );
    add(
      l10n.startDateLabel,
      job.startedAt == null ? null : formatJobDate(job.startedAt!, context),
    );
    add(
      l10n.completedDateLabel,
      job.completedAt == null
          ? null
          : formatJobDateTime(job.completedAt!, context),
    );
    add(l10n.createdAtLabel, formatJobDate(job.createdAt, context));
    add(l10n.expiresAtLabel, formatJobDate(job.expiresAt, context));

    return _FieldGrid(values: values);
  }
}

/// The customer belonging to THIS job, from [JobsState.selectedJobCustomer].
///
/// This is the ONLY customer surface a technician ever sees: read-only display
/// fields for the single job being opened. There are deliberately no
/// create/edit/delete/search actions and no list — those live in the
/// admin-only Customers feature. When the RPC returned nothing (another
/// technician's job, inactive employee, missing customer) the section shows a
/// short note instead of data.
class JobCustomerFields extends StatelessWidget {
  const JobCustomerFields({super.key, required this.state});

  final JobsState state;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final JobCustomerInfo? customer = state.selectedJobCustomer;

    if (customer == null) {
      return Text(
        l10n.customerInfoUnavailable,
        style: context.textStyles.bodyMedium?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      );
    }

    final List<(String, String)> values = <(String, String)>[];
    void add(String label, String? value) {
      if (value == null || value.trim().isEmpty) return;
      values.add((label, value.trim()));
    }

    add(l10n.customerNameLabel, customer.name);
    add(l10n.customerPhoneLabel, customer.phone);
    add(l10n.customerAddressLabel, customer.address);
    add(l10n.customerCityLabel, customer.city);
    add(l10n.customerPostalCodeLabel, customer.postalCode);

    return _FieldGrid(values: values);
  }
}

/// One column on a phone, two from ~520px up — the same breakpoint the form
/// screens use, so a tablet reads consistently across the feature.
class _FieldGrid extends StatelessWidget {
  const _FieldGrid({required this.values});

  final List<(String, String)> values;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth >= 520 ? 2 : 1;
        const double gap = AppSpacing.md;
        final double fieldWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: AppSpacing.lg,
          children: <Widget>[
            for (final (String label, String value) in values)
              SizedBox(
                width: fieldWidth,
                child: JobDetailField(label: label, value: value),
              ),
          ],
        );
      },
    );
  }
}
