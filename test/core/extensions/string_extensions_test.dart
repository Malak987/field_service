import 'package:field_service/core/extensions/string_extensions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StringX', () {
    test('treats whitespace-only strings as blank', () {
      expect(''.isBlank, isTrue);
      expect('   \n '.isBlank, isTrue);
      expect('job'.isBlank, isFalse);
      expect('  job  '.isNotBlank, isTrue);
    });

    test('converts blank strings to null for optional payload fields', () {
      expect('   '.nullIfBlank, isNull);
      expect('notes'.nullIfBlank, 'notes');
    });

    test('capitalizes only the first character', () {
      expect(''.capitalized, '');
      expect('kitchen installation'.capitalized, 'Kitchen installation');
      expect('already'.capitalized, 'Already');
    });
  });
}
