import 'package:drift/drift.dart';
import 'package:field_service/core/database/app_database.dart';
import 'package:field_service/features/jobs/data/models/job_model.dart';
import 'package:field_service/features/jobs/domain/entities/job.dart';

abstract interface class JobsLocalDataSource {
  Stream<List<Job>> watchAll({required String currentUserId, required bool isTechnician});

  Future<List<Job>> getAll({required String currentUserId, required bool isTechnician});

  Stream<Job?> watchById(String id);

  Future<Job?> getById(String id);

  Future<Job> insert(JobModel model);

  Future<void> mergeRemoteRows(
    List<JobModel> rows, {
    required Set<String> protectedEntityIds,
    required DateTime pulledAt,
  });
}

class DriftJobsLocalDataSource implements JobsLocalDataSource {
  const DriftJobsLocalDataSource(this._db);

  final AppDatabase _db;

  $JobsTableTable get _table => _db.jobsTable;

  @override
  Stream<List<Job>> watchAll({
    required String currentUserId,
    required bool isTechnician,
  }) {
    if (isTechnician) {
      final String cleanId = currentUserId.trim();
      if (cleanId.isEmpty) {
        return Stream<List<Job>>.value(const <Job>[]);
      }
      final $JobsTableTable t = _table;
      return (_db.select(t)
            ..where((t) => t.assignedEmployeeId.equals(cleanId))
            ..orderBy(<OrderingTerm Function($JobsTableTable)>[
              (t) => OrderingTerm.desc(t.createdAt),
              (t) => OrderingTerm.desc(t.id),
            ]))
          .watch()
          .map(
            (List<LocalJob> rows) =>
                rows.map(JobModel.fromLocalRow).toList(),
          );
    }

    final $JobsTableTable t = _table;
    return (_db.select(t)
          ..orderBy(<OrderingTerm Function($JobsTableTable)>[
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.id),
          ]))
        .watch()
        .map(
          (List<LocalJob> rows) =>
              rows.map(JobModel.fromLocalRow).toList(),
        );
  }

  @override
  Future<List<Job>> getAll({
    required String currentUserId,
    required bool isTechnician,
  }) async {
    if (isTechnician) {
      final String cleanId = currentUserId.trim();
      if (cleanId.isEmpty) {
        return const <Job>[];
      }
      final $JobsTableTable t = _table;
      final List<LocalJob> rows = await (_db.select(t)
            ..where((t) => t.assignedEmployeeId.equals(cleanId))
            ..orderBy(<OrderingTerm Function($JobsTableTable)>[
              (t) => OrderingTerm.desc(t.createdAt),
              (t) => OrderingTerm.desc(t.id),
            ]))
          .get();

      return rows.map(JobModel.fromLocalRow).toList();
    }

    final $JobsTableTable t = _table;
    final List<LocalJob> rows = await (_db.select(t)
          ..orderBy(<OrderingTerm Function($JobsTableTable)>[
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.id),
          ]))
        .get();

    return rows.map(JobModel.fromLocalRow).toList();
  }

  @override
  Stream<Job?> watchById(String id) {
    final $JobsTableTable t = _table;
    return (_db.select(t)..where((t) => t.id.equals(id))).watch().map(
      (List<LocalJob> rows) =>
          rows.isEmpty ? null : JobModel.fromLocalRow(rows.first),
    );
  }

  @override
  Future<Job?> getById(String id) async {
    final LocalJob? row = await (_db.select(
      _table,
    )..where((t) => t.id.equals(id))).getSingleOrNull();

    return row == null ? null : JobModel.fromLocalRow(row);
  }

  @override
  Future<Job> insert(JobModel model) async {
    await _db.into(_table).insertOnConflictUpdate(model.toLocalCompanion(isNew: true));
    return model;
  }

  @override
  Future<void> mergeRemoteRows(
    List<JobModel> rows, {
    required Set<String> protectedEntityIds,
    required DateTime pulledAt,
  }) {
    return _db.transaction(() async {
      for (final JobModel row in rows) {
        if (protectedEntityIds.contains(row.id)) {
          continue;
        }

        await _db
            .into(_table)
            .insertOnConflictUpdate(row.toLocalCompanion(isNew: false));
      }
    });
  }
}
