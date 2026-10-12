// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:field_service/core/utils/logger.dart';
import 'package:field_service/features/jobs/domain/entities/accessible_customer.dart';
import 'package:field_service/features/jobs/domain/entities/job_category.dart';
import 'package:field_service/features/jobs/domain/entities/new_customer_draft.dart';
import 'package:field_service/features/jobs/domain/entities/technician_job_creation.dart';
import 'package:field_service/features/jobs/domain/usecases/create_technician_customer_and_job.dart';
import 'package:field_service/features/jobs/domain/usecases/create_technician_job_for_customer.dart';
import 'package:field_service/features/jobs/domain/usecases/get_accessible_customers.dart';
import 'package:field_service/features/jobs/presentation/cubit/technician_job_form_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

/// Outcome of one submission attempt (typed so the page can pick the right
/// feedback and navigation without inspecting exceptions).
enum TechnicianJobFormOutcome {
  /// The server created the job; [TechnicianJobFormState.createdJob] holds
  /// the authoritative row (with the real job number).
  created,

  /// The device was offline: the creation is safely stored on it and will be
  /// pushed by the shared sync engine. Nothing was confirmed by the server.
  queuedForSync,

  /// The form is incomplete (no category, or no existing customer selected).
  /// Nothing was sent.
  invalid,

  /// A submission is already in flight — a repeated tap stays silent.
  inFlight,

  /// The server (or the network) refused the creation.
  failed,
}

/// Presentation state owner of the technician's "Create Customer & Job" form.
///
/// Registered as a **factory** in the DI container (one instance per page,
/// same convention as `CreateJobCubit`). All data access goes through use
/// cases:
/// * the two creation use cases — backed by the technician SECURITY DEFINER
///   RPCs; the server resolves the assignee from the caller's own identity,
///   so this cubit never handles an employee id at all,
/// * [GetAccessibleCustomers] — the customers this technician may work for
///   (never the admin customer list).
///
/// Idempotency: [idempotencyKey] is generated ONCE per form instance and
/// reused for every retry, so a double tap, a re-submitted form or a lost
/// acknowledgement can never create a second job (the repository derives the
/// stable job/customer/operation ids from it).
class TechnicianJobFormCubit extends Cubit<TechnicianJobFormState> {
  TechnicianJobFormCubit({
    required CreateTechnicianCustomerAndJob createCustomerAndJob,
    required CreateTechnicianJobForCustomer createJobForCustomer,
    required GetAccessibleCustomers getAccessibleCustomers,
    Uuid? uuid,
  }) : _createCustomerAndJob = createCustomerAndJob,
       _createJobForCustomer = createJobForCustomer,
       _getAccessibleCustomers = getAccessibleCustomers,
       idempotencyKey = (uuid ?? const Uuid()).v4(),
       super(const TechnicianJobFormState());

  final CreateTechnicianCustomerAndJob _createCustomerAndJob;
  final CreateTechnicianJobForCustomer _createJobForCustomer;
  final GetAccessibleCustomers _getAccessibleCustomers;

  /// Stable identity of THIS form: one key, one job — however often the
  /// technician retries.
  final String idempotencyKey;

  /// Loads the customers this technician may create a job for.
  ///
  /// Best effort by design: the read is a server-side authorization query,
  /// so offline (or when it is refused) the form simply stays in "new
  /// customer" mode and says so — it never invents a customer list.
  Future<void> loadAccessibleCustomers({String search = ''}) async {
    if (isClosed) {
      return;
    }

    emit(state.copyWith(isLoadingCustomers: true, customersFailed: false));

    try {
      final List<AccessibleCustomer> customers = await _getAccessibleCustomers(
        search: search,
      );
      if (!isClosed) {
        emit(
          state.copyWith(
            accessibleCustomers: customers,
            isLoadingCustomers: false,
            customersFailed: false,
            // A selected customer that the server no longer returns (blocked
            // meanwhile, search filter) must not stay selected.
            clearSelectedCustomerId:
                state.selectedCustomerId != null &&
                !customers.any(
                  (AccessibleCustomer c) =>
                      c.id == state.selectedCustomerId,
                ),
          ),
        );
      }
    } catch (error, stackTrace) {
      AppLogger.warning(
        'The accessible customers could not be loaded.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!isClosed) {
        emit(state.copyWith(isLoadingCustomers: false, customersFailed: true));
      }
    }
  }

  /// Switches between "new customer" and "existing customer".
  ///
  /// Leaving the existing-customer mode clears the selection so a stale id
  /// can never be submitted with the wrong mode.
  void selectMode(TechnicianJobCustomerMode mode) {
    if (isClosed || mode == state.mode) {
      return;
    }

    emit(
      state.copyWith(
        mode: mode,
        clearSelectedCustomerId: mode == TechnicianJobCustomerMode.newCustomer,
        showValidationErrors: false,
      ),
    );

    if (mode == TechnicianJobCustomerMode.existingCustomer &&
        state.accessibleCustomers.isEmpty &&
        !state.isLoadingCustomers) {
      // Lazy load: the list is only needed in this mode. The load never
      // throws — a failure lands in the state as [customersFailed].
      unawaited(loadAccessibleCustomers());
    }
  }

  /// Selects one of the two supported categories. Unsupported values are
  /// ignored — the selector only ever offers `JobCategory.supportedValues`.
  void selectCategory(String? category) {
    if (!isClosed && (category == null || JobCategory.isSupported(category))) {
      emit(state.copyWith(selectedCategory: category));
    }
  }

  /// Selects an existing customer (only in existing-customer mode).
  void selectCustomer(String? customerId) {
    if (isClosed) {
      return;
    }
    emit(
      state.copyWith(
        selectedCustomerId: customerId,
        clearSelectedCustomerId: customerId == null,
      ),
    );
  }

  /// Creates a NEW customer and their job in one server-side unit.
  Future<TechnicianJobFormOutcome> submitNewCustomerAndJob({
    required NewCustomerDraft customer,
    String? description,
  }) {
    if (state.mode != TechnicianJobCustomerMode.newCustomer) {
      return Future<TechnicianJobFormOutcome>.value(
        TechnicianJobFormOutcome.invalid,
      );
    }

    return _submit(
      () => _createCustomerAndJob(
        customer: customer,
        jobType: state.selectedCategory!,
        description: description,
        idempotencyKey: idempotencyKey,
      ),
    );
  }

  /// Creates a job for the selected EXISTING customer.
  Future<TechnicianJobFormOutcome> submitJobForExistingCustomer({
    String? description,
  }) {
    if (state.mode != TechnicianJobCustomerMode.existingCustomer ||
        state.selectedCustomerId == null) {
      return Future<TechnicianJobFormOutcome>.value(
        TechnicianJobFormOutcome.invalid,
      );
    }

    return _submit(
      () => _createJobForCustomer(
        customerId: state.selectedCustomerId!,
        jobType: state.selectedCategory!,
        description: description,
        idempotencyKey: idempotencyKey,
      ),
    );
  }

  /// The shared submission path: one double-tap guard, one validation gate,
  /// one place that decides between "server confirmed" and "queued".
  Future<TechnicianJobFormOutcome> _submit(
    Future<TechnicianJobCreation> Function() action,
  ) async {
    if (isClosed) {
      return TechnicianJobFormOutcome.failed;
    }
    if (state.isSubmitting) {
      return TechnicianJobFormOutcome.inFlight;
    }
    if (!state.isComplete) {
      emit(state.copyWith(showValidationErrors: true));
      return TechnicianJobFormOutcome.invalid;
    }

    emit(state.copyWith(isSubmitting: true, clearError: true));

    try {
      final TechnicianJobCreation creation = await action();
      if (isClosed) {
        return creation.isCreated
            ? TechnicianJobFormOutcome.created
            : TechnicianJobFormOutcome.queuedForSync;
      }
      emit(
        state.copyWith(
          isSubmitting: false,
          createdJob: creation.job,
          queuedJobId: creation.isPendingSync ? creation.jobId : null,
        ),
      );
      return creation.isCreated
          ? TechnicianJobFormOutcome.created
          : TechnicianJobFormOutcome.queuedForSync;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'The technician job creation failed.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!isClosed) {
        emit(state.copyWith(isSubmitting: false, error: error));
      }
      return TechnicianJobFormOutcome.failed;
    }
  }
}
