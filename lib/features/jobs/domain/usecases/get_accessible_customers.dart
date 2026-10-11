import 'package:field_service/features/jobs/domain/entities/accessible_customer.dart';
import 'package:field_service/features/jobs/domain/repositories/jobs_repository.dart';

/// Use case: the customers the CURRENT technician may create a job for.
///
/// Deliberately NOT the admin customer list: the backing RPC returns only
/// customers already referenced by a job assigned to the caller's own active
/// employee row. `public.customers` stays admin-only in RLS and the
/// technician gets no general customer read.
class GetAccessibleCustomers {
  const GetAccessibleCustomers(this._repository);

  final JobsRepository _repository;

  Future<List<AccessibleCustomer>> call({String search = ''}) {
    return _repository.getAccessibleCustomers(search: search);
  }
}
