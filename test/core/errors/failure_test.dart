import 'package:field_service/core/errors/failure.dart';
import 'package:field_service/core/errors/failures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Failure', () {
    test('exposes its kind, message and code', () {
      const ServerFailure failure = ServerFailure(
        message: 'Job could not be saved',
        code: '42501',
      );

      expect(failure.type, FailureType.server);
      expect(failure.message, 'Job could not be saved');
      expect(failure.code, '42501');
    });

    test('compares equal when kind, message and code match', () {
      const Failure first = ServerFailure(message: 'boom', code: '500');
      const Failure second = ServerFailure(message: 'boom', code: '500');

      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);
    });

    test('never compares equal across kinds, even with the same message', () {
      const Failure server = ServerFailure(message: 'offline');
      const Failure network = NetworkFailure(message: 'offline');

      expect(server, isNot(equals(network)));
    });

    test('ignores the underlying cause when comparing', () {
      final Failure withCause = ServerFailure(
        message: 'x',
        cause: StateError('low level detail'),
      );
      const Failure withoutCause = ServerFailure(message: 'x');

      expect(withCause, equals(withoutCause));
    });

    test('has a readable representation for logs', () {
      const Failure failure = CacheFailure(message: 'disk full', code: '13');

      expect(failure.toString(), 'CacheFailure(message: disk full, code: 13)');
    });
  });
}
