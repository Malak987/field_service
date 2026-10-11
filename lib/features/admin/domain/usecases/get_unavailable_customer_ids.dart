import 'package:field_service/features/admin/domain/repositories/admin_repository.dart';

/// Use case: the ids of the customers that must NOT be offered for a new job
/// (blocked or soft deleted).
///
/// Consumed by the admin Create Job screen to keep such customers out of the
/// selector. The authoritative refusal stays inside the `create_job` RPC, so a
/// stale/offline client can never create a job for a blocked customer.
class GetUnavailableCustomerIds {
  const GetUnavailableCustomerIds(this._repository);

  final AdminRepository _repository;

  Future<Set<String>> call() => _repository.unavailableCustomerIds();
}
