import 'package:field_service/core/sync/sync_operation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncOperation', () {
    final DateTime createdAt = DateTime.utc(2026, 10, 2, 8, 30);

    SyncOperation buildOperation() => SyncOperation(
      id: 'op-1',
      entityType: SyncEntityType.job,
      entityId: 'job-1',
      type: SyncOperationType.create,
      payload: <String, Object?>{'title': 'Kitchen installation'},
      createdAt: createdAt,
    );

    test('starts as a fresh pending operation', () {
      final SyncOperation operation = buildOperation();

      expect(operation.status, SyncOperationStatus.pending);
      expect(operation.attempts, 0);
      expect(operation.lastAttemptAt, isNull);
      expect(operation.errorMessage, isNull);
    });

    test('keeps identity when a copy changes state', () {
      final SyncOperation pending = buildOperation();
      final SyncOperation failed = pending.copyWith(
        status: SyncOperationStatus.failed,
        attempts: pending.attempts + 1,
        errorMessage: 'timeout',
      );

      expect(failed.id, pending.id);
      expect(failed.entityId, pending.entityId);
      expect(failed.payload, pending.payload);
      expect(failed.createdAt, createdAt);
      expect(failed.status, SyncOperationStatus.failed);
      expect(failed.attempts, 1);
      expect(failed.errorMessage, 'timeout');
      // The original is untouched: states are immutable.
      expect(pending.status, SyncOperationStatus.pending);
    });

    test('compares equal when the queued change is identical', () {
      expect(buildOperation(), equals(buildOperation()));
      expect(buildOperation().hashCode, buildOperation().hashCode);
    });

    test('differs as soon as the queued change differs', () {
      final SyncOperation update = buildOperation().copyWith(); // same fields
      final SyncOperation sameOp = SyncOperation(
        id: 'op-1',
        entityType: SyncEntityType.job,
        entityId: 'job-1',
        type: SyncOperationType.update,
        payload: <String, Object?>{'title': 'Kitchen installation'},
        createdAt: createdAt,
      );

      expect(update, equals(buildOperation()));
      expect(sameOp, isNot(equals(buildOperation())));
    });
  });
}
