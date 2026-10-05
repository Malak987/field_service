import 'package:field_service/features/customers/domain/repositories/customers_repository.dart';

/// Use case: pull the visible remote customers into Drift.
///
/// The repository checks connectivity itself and merges without overwriting
/// rows that still have unfinished queue operations, so a refresh is always
/// safe to call — offline it is a no-op, online it refreshes the local mirror
/// the UI is already streaming from.
class RefreshCustomers {
  const RefreshCustomers(this._repository);

  final CustomersRepository _repository;

  Future<void> call() => _repository.refreshFromRemote();
}
