import 'package:field_service/features/employees/data/datasources/employees_remote_data_source.dart';
import 'package:field_service/features/employees/domain/entities/employee.dart';
import 'package:field_service/features/employees/domain/repositories/employees_repository.dart';

/// Data-layer implementation of [EmployeesRepository].
///
/// Reads delegate to [EmployeesRemoteDataSource]; visibility is enforced by
/// the existing employees RLS (active admin: all rows), never in this layer.
class EmployeesRepositoryImpl implements EmployeesRepository {
  EmployeesRepositoryImpl(this._remoteDataSource);

  final EmployeesRemoteDataSource _remoteDataSource;

  @override
  Future<List<Employee>> getActiveTechnicians() {
    return _remoteDataSource.getActiveTechnicians();
  }
}
