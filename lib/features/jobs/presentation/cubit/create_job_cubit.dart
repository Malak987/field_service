// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:field_service/core/utils/logger.dart';
import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/customers/domain/usecases/get_customers.dart';
import 'package:field_service/features/customers/domain/usecases/refresh_customers.dart';
import 'package:field_service/features/employees/domain/entities/employee.dart';
import 'package:field_service/features/employees/domain/usecases/get_active_technicians.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/usecases/create_job.dart';
import 'package:field_service/features/jobs/presentation/cubit/create_job_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Outcome of a Create & Assign attempt (typed so the page can pick the
/// right feedback without inspecting exceptions).
enum CreateJobOutcome {
  /// The server created and assigned the job; [CreateJobState.createdJob]
  /// holds the authoritative row.
  created,

  /// The form is incomplete (customer, category or technician missing).
  /// Nothing was sent.
  invalid,

  /// A submission is already in flight — a repeated tap stays silent.
  inFlight,

  /// The server (or the network) refused the creation.
  failed,
}

/// Presentation state owner of the admin Create Job form.
///
/// Registered as a **factory** in the DI container: the Create Job page owns
/// its instance (same convention as [JobsCubit]). All data access goes
/// through use cases:
/// * customers — the EXISTING offline-first Customers feature (Drift stream,
///   never a second customer store). The stream is local-only BY DESIGN, so
///   opening this page also nudges the EXISTING [RefreshCustomers] pull:
///   online it merges the backend's customers into the mirror the dropdown
///   streams from (the Customers page does the same); offline it is a no-op
///   and the mirror stays the answer,
/// * technicians — the Employees read (ACTIVE technicians only),
/// * submission — the `create_job` RPC via [CreateJob]; the server stamps
///   `assigned_at` and the job number, the client never invents either.
class CreateJobCubit extends Cubit<CreateJobState> {
  CreateJobCubit({
    required GetCustomers getCustomers,
    required GetActiveTechnicians getActiveTechnicians,
    required CreateJob createJob,
    required RefreshCustomers refreshCustomers,
  }) : _getCustomers = getCustomers,
       _getActiveTechnicians = getActiveTechnicians,
       _createJob = createJob,
       _refreshCustomers = refreshCustomers,
       super(const CreateJobState());

  final GetCustomers _getCustomers;
  final GetActiveTechnicians _getActiveTechnicians;
  final CreateJob _createJob;
  final RefreshCustomers _refreshCustomers;

  StreamSubscription<List<Customer>>? _customersSubscription;

  /// Loads both selector options: the live customer stream (offline-first
  /// Drift) and the one-shot active-technician list.
  Future<void> loadOptions() async {
    if (isClosed) {
      return;
    }

    // The customer dropdown streams the LOCAL mirror — the single source of
    // truth (offline-first rule). On a device whose mirror is still empty
    // (fresh install / data cleared / never opened the Customers page) the
    // dropdown would otherwise have nothing to offer: nudge the EXISTING
    // remote pull, which merges backend rows into exactly that mirror — the
    // stream then delivers them here. The pull checks connectivity itself
    // (offline = safe no-op) and any failure only logs: the mirror, not the
    // network, decides what the form shows.
    unawaited(
      _refreshCustomers().catchError((Object error, StackTrace stackTrace) {
        AppLogger.warning(
          'Customer options for Create Job could not be refreshed from the '
          'backend; the local mirror stays the answer.',
          error: error,
          stackTrace: stackTrace,
        );
      }),
    );

    _customersSubscription ??= _getCustomers().listen(
      (List<Customer> customers) {
        if (!isClosed) {
          emit(state.copyWith(customers: customers, isLoadingOptions: false));
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.warning(
          'Customer options for Create Job could not be read.',
          error: error,
          stackTrace: stackTrace,
        );
        if (!isClosed) {
          emit(state.copyWith(isLoadingOptions: false));
        }
      },
    );

    try {
      final List<Employee> technicians = await _getActiveTechnicians();

      // Surface (do not hide) unexpected data problems: an employee row
      // without a name falls back to its employee code in the UI.
      for (final Employee technician in technicians) {
        if (technician.hasMissingName) {
          AppLogger.warning(
            'Employee "${technician.employeeCode ?? technician.id}" has no '
            'name in public.employees; showing the employee code instead. '
            'Fix the row in Supabase to restore the real name.',
          );
        }
      }

      if (!isClosed) {
        emit(state.copyWith(technicians: technicians, isLoadingOptions: false));
      }
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Technician options for Create Job could not be loaded.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!isClosed) {
        emit(state.copyWith(isLoadingOptions: false));
      }
    }
  }

  void selectCustomer(String? customerId) {
    if (!isClosed) {
      emit(state.copyWith(selectedCustomerId: customerId));
    }
  }

  /// Selects one of the two supported categories. Unsupported values are
  /// ignored — the selector only ever offers [JobCategory.supportedValues].
  void selectCategory(String? category) {
    if (!isClosed && (category == null || JobCategory.isSupported(category))) {
      emit(state.copyWith(selectedCategory: category));
    }
  }

  void setDescription(String text) {
    if (!isClosed) {
      emit(state.copyWith(description: text));
    }
  }

  void selectTechnician(String? employeeId) {
    if (!isClosed) {
      emit(state.copyWith(selectedTechnicianId: employeeId));
    }
  }

  /// Submits the form: creates the job AND assigns it (one server action).
  ///
  /// The server is authoritative for the job number, `status = 'assigned'`,
  /// the `assigned_at` timestamp and the events; a successful result exposes
  /// the returned row via [CreateJobState.createdJob].
  Future<CreateJobOutcome> submit() async {
    if (isClosed) {
      return CreateJobOutcome.failed;
    }
    if (state.isSubmitting) {
      return CreateJobOutcome.inFlight;
    }
    if (!state.isComplete) {
      emit(state.copyWith(showValidationErrors: true));
      return CreateJobOutcome.invalid;
    }

    emit(state.copyWith(isSubmitting: true, clearError: true));

    try {
      final String description = state.description.trim();
      final job = await _createJob(
        customerId: state.selectedCustomerId!,
        jobType: state.selectedCategory!,
        description: description.isEmpty ? null : description,
        assignedEmployeeId: state.selectedTechnicianId!,
      );
      if (!isClosed) {
        emit(state.copyWith(isSubmitting: false, createdJob: job));
      }
      return CreateJobOutcome.created;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Create & Assign Job failed.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!isClosed) {
        emit(state.copyWith(isSubmitting: false, error: error));
      }
      return CreateJobOutcome.failed;
    }
  }

  @override
  Future<void> close() {
    final StreamSubscription<List<Customer>>? subscription =
        _customersSubscription;
    _customersSubscription = null;
    unawaited(subscription?.cancel());
    return super.close();
  }
}
