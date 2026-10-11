import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';
import 'package:field_service/features/jobs/presentation/utils/technician_job_form_validators.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests of the technician form's validation rules.
///
/// Pure Dart: the rules are static and take [AppLocalizations], so both
/// languages are asserted without a widget tree.
void main() {
  const AppLocalizations en = AppLocalizationsEn();
  const AppLocalizations de = AppLocalizationsDe();

  group('required fields', () {
    test('name is required', () {
      expect(
        TechnicianJobFormValidators.validateName(null, en),
        en.validationRequiredField,
      );
      expect(TechnicianJobFormValidators.validateName('', en), isNotNull);
      expect(TechnicianJobFormValidators.validateName('   ', en), isNotNull);
      expect(TechnicianJobFormValidators.validateName('Anna Weber', en), isNull);
    });

    test('address is required (the backend column is NOT NULL)', () {
      expect(
        TechnicianJobFormValidators.validateAddress(null, en),
        en.validationRequiredField,
      );
      expect(TechnicianJobFormValidators.validateAddress('  ', en), isNotNull);
      expect(
        TechnicianJobFormValidators.validateAddress('Hauptstraße 12', en),
        isNull,
      );
    });

    test('the required message is localized in both languages', () {
      expect(
        TechnicianJobFormValidators.validateName(null, de),
        de.validationRequiredField,
      );
      expect(
        TechnicianJobFormValidators.validateName(null, de),
        isNot(en.validationRequiredField),
      );
    });
  });

  group('maximum lengths', () {
    test('name is rejected beyond the agreed limit', () {
      final String tooLong = 'a' *
          (JobsRepository.maxCustomerNameLength + 1);
      expect(
        TechnicianJobFormValidators.validateName(tooLong, en),
        en.validationFieldTooLong(JobsRepository.maxCustomerNameLength),
      );
      // Exactly at the limit is still valid.
      final String atLimit = 'a' * JobsRepository.maxCustomerNameLength;
      expect(TechnicianJobFormValidators.validateName(atLimit, en), isNull);
    });

    test('address, city, postal code and notes honour their own limits', () {
      expect(
        TechnicianJobFormValidators.validateAddress(
          'a' * (JobsRepository.maxCustomerAddressLength + 1),
          en,
        ),
        isNotNull,
      );
      expect(
        TechnicianJobFormValidators.validateOptionalCity(
          'a' * (JobsRepository.maxCustomerCityLength + 1),
          en,
        ),
        isNotNull,
      );
      expect(
        TechnicianJobFormValidators.validateOptionalPostalCode(
          'a' * (JobsRepository.maxCustomerPostalCodeLength + 1),
          en,
        ),
        isNotNull,
      );
      expect(
        TechnicianJobFormValidators.validateOptionalNotes(
          'a' * (JobsRepository.maxCustomerNotesLength + 1),
          en,
        ),
        isNotNull,
      );
      expect(
        TechnicianJobFormValidators.validateJobDescription(
          'a' * (JobsRepository.maxJobDescriptionLength + 1),
          en,
        ),
        isNotNull,
      );
    });

    test('the length message carries the limit and is localized', () {
      expect(
        en.validationFieldTooLong(20),
        contains('20'),
      );
      expect(
        de.validationFieldTooLong(20),
        contains('20'),
      );
      expect(de.validationFieldTooLong(20), isNot(en.validationFieldTooLong(20)));
    });
  });

  group('optional email', () {
    test('blank is valid (the field is optional)', () {
      expect(TechnicianJobFormValidators.validateOptionalEmail(null, en), isNull);
      expect(TechnicianJobFormValidators.validateOptionalEmail('', en), isNull);
      expect(
        TechnicianJobFormValidators.validateOptionalEmail('   ', en),
        isNull,
      );
    });

    test('a filled value must be a real address', () {
      expect(
        TechnicianJobFormValidators.validateOptionalEmail('anna@example.com', en),
        isNull,
      );
      expect(
        TechnicianJobFormValidators.validateOptionalEmail('anna@', en),
        en.validationEmailInvalid,
      );
      expect(
        TechnicianJobFormValidators.validateOptionalEmail('not-an-email', en),
        en.validationEmailInvalid,
      );
    });

    test('over-length addresses are rejected', () {
      final String tooLong =
          '${'a' * JobsRepository.maxCustomerEmailLength}@example.com';
      expect(
        TechnicianJobFormValidators.validateOptionalEmail(tooLong, en),
        en.validationFieldTooLong(JobsRepository.maxCustomerEmailLength),
      );
    });
  });

  group('optional phone', () {
    test('blank is valid', () {
      expect(
        TechnicianJobFormValidators.validateOptionalPhone(null, en),
        isNull,
      );
      expect(TechnicianJobFormValidators.validateOptionalPhone('  ', en), isNull);
    });

    test('realistic numbers pass, including separators and country codes', () {
      for (final String phone in <String>[
        '+49 151 23456789',
        '015123456789',
        '(030) 123 456 78',
        '0049-30-12345678',
        '+43 660 1234567',
      ]) {
        expect(
          TechnicianJobFormValidators.validateOptionalPhone(phone, en),
          isNull,
          reason: 'expected "$phone" to be accepted',
        );
      }
    });

    test('values that cannot be a phone number are refused', () {
      for (final String phone in <String>[
        'abc',
        '12345', // fewer than the minimum digits
        'call me maybe',
        '++49++',
      ]) {
        expect(
          TechnicianJobFormValidators.validateOptionalPhone(phone, en),
          en.validationPhoneInvalid,
          reason: 'expected "$phone" to be refused',
        );
      }
    });

    test('over-length values are refused', () {
      final String tooLong =
          '0' * (JobsRepository.maxCustomerPhoneLength + 1);
      expect(
        TechnicianJobFormValidators.validateOptionalPhone(tooLong, en),
        en.validationFieldTooLong(JobsRepository.maxCustomerPhoneLength),
      );
    });
  });

  group('optional free text', () {
    test('blank optional fields never fail', () {
      expect(TechnicianJobFormValidators.validateOptionalCity('', en), isNull);
      expect(
        TechnicianJobFormValidators.validateOptionalPostalCode(null, en),
        isNull,
      );
      expect(TechnicianJobFormValidators.validateOptionalNotes('', en), isNull);
      expect(TechnicianJobFormValidators.validateJobDescription('', en), isNull);
    });

    test('reasonable values pass', () {
      expect(
        TechnicianJobFormValidators.validateOptionalCity('Berlin', en),
        isNull,
      );
      expect(
        TechnicianJobFormValidators.validateOptionalPostalCode('10115', en),
        isNull,
      );
      expect(
        TechnicianJobFormValidators.validateOptionalNotes(
          'Backyard entrance, ring twice.',
          en,
        ),
        isNull,
      );
      expect(
        TechnicianJobFormValidators.validateJobDescription(
          'Renew the kitchen fronts and the worktop.',
          en,
        ),
        isNull,
      );
    });
  });
}
