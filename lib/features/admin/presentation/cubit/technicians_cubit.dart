import 'package:equatable/equatable.dart';
import 'package:field_service/core/utils/logger.dart';
import 'package:field_service/features/admin/domain/entities/admin_account_status.dart';
import 'package:field_service/features/admin/domain/entities/admin_failure.dart';
import 'package:field_service/features/admin/domain/entities/managed_employee.dart';
import 'package:field_service/features/admin/domain/usecases/list_managed_employees.dart';
import 'package:field_service/features/admin/domain/usecases/set_employee_status.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Loading state of the technician management list.
enum TechniciansStatus { initial, loading, success, failure }

/// State of the `إدارة الفنيين / Manage Technicians` screen.
class TechniciansState extends Equatable {
  const TechniciansState({
    this.status = TechniciansStatus.initial,
    this.employees = const <ManagedEmployee>[],
    this.isBusy = false,
    this.busyEmployeeId,
    this.loadFailure,
  });

  final TechniciansStatus status;

  /// Every employee row the server returned (technicians + admins; the UI only
  /// offers actions on technician rows).
  final List<ManagedEmployee> employees;

  /// A management action (block / unblock / soft delete) is in flight.
  final bool isBusy;

  /// Employee whose action is in flight — its row shows a spinner.
  final String? busyEmployeeId;

  /// Why the LIST could not be loaded (an action failure is returned by the
  /// cubit method instead, so it can be shown as a message immediately).
  final AdminFailureKind? loadFailure;

  bool get hasEmployees => employees.isNotEmpty;

  TechniciansState copyWith({
    TechniciansStatus? status,
    List<ManagedEmployee>? employees,
    bool? isBusy,
    String? busyEmployeeId,
    bool clearBusyEmployeeId = false,
    AdminFailureKind? loadFailure,
    bool clearLoadFailure = false,
  }) {
    return TechniciansState(
      status: status ?? this.status,
      employees: employees ?? this.employees,
      isBusy: isBusy ?? this.isBusy,
      busyEmployeeId: clearBusyEmployeeId
          ? null
          : (busyEmployeeId ?? this.busyEmployeeId),
      loadFailure: clearLoadFailure ? null : (loadFailure ?? this.loadFailure),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    employees,
    isBusy,
    busyEmployeeId,
    loadFailure,
  ];
}

/// State holder of the technician management screen.
///
/// Thin by design: the authorization ("only an active admin may manage
/// accounts", "an admin never manages their own account", "a soft deleted
/// technician is never reactivated", "never a hard delete") is implemented in
/// the database; this cubit only loads the list and applies the transitions the
/// admin confirmed in the UI, surfacing the typed failure for the message.
class TechniciansCubit extends Cubit<TechniciansState> {
  TechniciansCubit({
    required ListManagedEmployees listManagedEmployees,
    required SetEmployeeStatus setEmployeeStatus,
  }) : _listManagedEmployees = listManagedEmployees,
       _setEmployeeStatus = setEmployeeStatus,
       super(const TechniciansState());

  final ListManagedEmployees _listManagedEmployees;
  final SetEmployeeStatus _setEmployeeStatus;

  /// Loads (or reloads) every employee row from the server.
  Future<void> load() async {
    emit(
      state.copyWith(
        status: TechniciansStatus.loading,
        clearLoadFailure: true,
      ),
    );

    try {
      final List<ManagedEmployee> employees = await _listManagedEmployees();
      if (isClosed) {
        return;
      }
      emit(
        TechniciansState(
          status: TechniciansStatus.success,
          employees: employees,
        ),
      );
    } on AdminFailure catch (failure, stackTrace) {
      _log('The technician list could not be loaded.', failure, stackTrace);
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          status: TechniciansStatus.failure,
          loadFailure: failure.kind,
        ),
      );
    } catch (error, stackTrace) {
      _log('The technician list could not be loaded.', error, stackTrace);
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          status: TechniciansStatus.failure,
          loadFailure: AdminFailureKind.unknown,
        ),
      );
    }
  }

  /// Blocks the technician (server: `account_status = 'blocked'`,
  /// `is_active = false`). Returns `null` on success, otherwise why it failed.
  Future<AdminFailureKind?> block(ManagedEmployee employee) =>
      _apply(employee, AdminAccountStatus.blocked);

  /// Unblocks a blocked technician. Refused for soft deleted accounts.
  Future<AdminFailureKind?> unblock(ManagedEmployee employee) =>
      _apply(employee, AdminAccountStatus.active);

  /// SOFT deletes the technician: the row, the Auth account, the assigned jobs,
  /// the photos and the signatures all stay in the database.
  Future<AdminFailureKind?> softDelete(ManagedEmployee employee) =>
      _apply(employee, AdminAccountStatus.deleted);

  Future<AdminFailureKind?> _apply(
    ManagedEmployee employee,
    AdminAccountStatus status,
  ) async {
    if (state.isBusy) {
      // One management action at a time — never two concurrent transitions.
      return null;
    }

    emit(
      state.copyWith(isBusy: true, busyEmployeeId: employee.id),
    );

    try {
      final ManagedEmployee updated = await _setEmployeeStatus(
        employeeId: employee.id,
        status: status,
      );
      if (isClosed) {
        return null;
      }
      emit(
        state.copyWith(
          status: TechniciansStatus.success,
          employees: _replace(state.employees, updated),
          isBusy: false,
          clearBusyEmployeeId: true,
          clearLoadFailure: true,
        ),
      );
      return null;
    } on AdminFailure catch (failure, stackTrace) {
      _log(
        'Changing the status of "${employee.displayName}" was refused.',
        failure,
        stackTrace,
      );
      if (!isClosed) {
        emit(state.copyWith(isBusy: false, clearBusyEmployeeId: true));
      }
      return failure.kind;
    } catch (error, stackTrace) {
      _log(
        'Changing the status of "${employee.displayName}" failed.',
        error,
        stackTrace,
      );
      if (!isClosed) {
        emit(state.copyWith(isBusy: false, clearBusyEmployeeId: true));
      }
      return AdminFailureKind.unknown;
    }
  }

  List<ManagedEmployee> _replace(
    List<ManagedEmployee> employees,
    ManagedEmployee updated,
  ) {
    final List<ManagedEmployee> next = <ManagedEmployee>[
      for (final ManagedEmployee employee in employees)
        if (employee.id == updated.id) updated else employee,
    ];
    // The row was not part of the list (defensive): append it instead of
    // silently dropping a server-returned record.
    if (!employees.any((ManagedEmployee e) => e.id == updated.id)) {
      next.add(updated);
    }
    return next;
  }

  void _log(String message, Object error, StackTrace stackTrace) {
    AppLogger.warning(message, error: error, stackTrace: stackTrace);
  }
}
