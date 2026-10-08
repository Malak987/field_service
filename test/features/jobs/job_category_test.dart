import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/presentation/utils/job_label_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

/// The business has EXACTLY two job categories. These tests lock that rule
/// at the domain level ([JobCategory]) and at the presentation level
/// ([JobLabelMapper] — stable value in, localized label out, legacy values
/// never produce a legacy label).
void main() {
  group('JobCategory', () {
    test('supports exactly the two business categories', () {
      expect(JobCategory.supportedValues, <String>[
        'home_renovation',
        'kitchen_renovation',
      ]);
      expect(JobCategory.supportedValues, hasLength(2));
    });

    test('isSupported accepts only the two stable values', () {
      expect(JobCategory.isSupported(JobCategory.homeRenovation), isTrue);
      expect(JobCategory.isSupported(JobCategory.kitchenRenovation), isTrue);

      expect(JobCategory.isSupported('renovation'), isFalse);
      expect(JobCategory.isSupported('kitchen_installation'), isFalse);
      expect(JobCategory.isSupported('maintenance'), isFalse);
      expect(JobCategory.isSupported('Kitchen Installation'), isFalse);
      expect(JobCategory.isSupported(''), isFalse);
      expect(JobCategory.isSupported(null), isFalse);
    });

    test('equality is by stable value', () {
      expect(
        const JobCategory('kitchen_renovation'),
        const JobCategory(JobCategory.kitchenRenovation),
      );
      expect(
        const JobCategory('home_renovation') ==
            const JobCategory('kitchen_renovation'),
        isFalse,
      );
    });
  });

  group('JobLabelMapper categories', () {
    const JobLabelMapper en = JobLabelMapper(AppLocalizationsEn());
    const JobLabelMapper de = JobLabelMapper(AppLocalizationsDe());

    test('maps the two stable values to localized labels (EN)', () {
      expect(en.jobTypeLabel(JobCategory.homeRenovation), 'Home Renovation');
      expect(
        en.jobTypeLabel(JobCategory.kitchenRenovation),
        'Kitchen Renovation',
      );
    });

    test('maps the two stable values to localized labels (DE)', () {
      expect(de.jobTypeLabel(JobCategory.homeRenovation), 'Hausrenovierung');
      expect(
        de.jobTypeLabel(JobCategory.kitchenRenovation),
        'Küchenrenovierung',
      );
    });

    test('legacy values never resurface as legacy labels', () {
      // Migrated on the server to the two supported values; should one leak
      // through, the UI displays the raw value — never "Kitchen Installation"
      // or any other retired category name.
      expect(
        en.jobTypeLabel('kitchen_installation'),
        'kitchen_installation',
        reason: 'legacy value must not map to a legacy label',
      );
      expect(en.jobTypeLabel('renovation'), 'renovation');
      expect(en.jobTypeLabel('maintenance'), 'maintenance');
    });
  });
}
