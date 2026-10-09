import 'dart:async';

import 'package:field_service/app/di/injection.dart';
import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/features/customers/domain/entities/customer.dart';
import 'package:field_service/features/customers/domain/repositories/customers_repository.dart';
import 'package:field_service/features/customers/domain/usecases/create_customer.dart';
import 'package:field_service/features/customers/domain/usecases/delete_customer.dart';
import 'package:field_service/features/customers/domain/usecases/get_customer_by_id.dart';
import 'package:field_service/features/customers/domain/usecases/get_customers.dart';
import 'package:field_service/features/customers/domain/usecases/refresh_customers.dart';
import 'package:field_service/features/customers/domain/usecases/update_customer.dart';
import 'package:field_service/features/customers/presentation/cubit/customers_cubit.dart';
import 'package:field_service/features/customers/presentation/pages/create_customer_page.dart';
import 'package:field_service/features/customers/presentation/pages/customers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_test_harness.dart';
import '../../support/test_authentication_repository.dart';

void main() {
  late AppTestHarness app;
  setUp(() => app = AppTestHarness());
  tearDown(() => app.dispose());

  _testCustomers('customers loading, empty, error and retry states', (
    tester,
  ) async {
    final _CustomersRepositoryFake repository = _CustomersRepositoryFake();
    addTearDown(repository.dispose);
    await app.configure(user: adminUser, withCustomers: true);
    await _registerCustomersCubit(repository);
    await app.pump(tester);

    await tester.tap(find.text('Customers'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CustomersPage), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.emitCustomers(const <Customer>[]);
    await tester.pumpAndSettle();
    expect(find.text('0 customers'), findsOneWidget);
    expect(find.text('No customers'), findsOneWidget);

    repository.emitError(StateError('stream read failed'));
    await tester.pump();
    expect(find.text('Customers could not be loaded'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);

    await tester.tap(find.text('Try Again'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.emitCustomers(const <Customer>[]);
    await tester.pumpAndSettle();
    expect(find.text('No customers'), findsOneWidget);
  });

  _testCustomers('create form validates and retains fields after save failure', (
    tester,
  ) async {
    final _CustomersRepositoryFake repository = _CustomersRepositoryFake()
      ..createError = StateError('local write failed');
    addTearDown(repository.dispose);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await app.configure(user: adminUser, withCustomers: true);
    await _registerCustomersCubit(repository);
    await app.pump(tester);

    await tester.tap(find.text('Customers'));
    await tester.pump(const Duration(milliseconds: 400));
    repository.emitCustomers(const <Customer>[]);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add_customer_fab')));
    await tester.pumpAndSettle();
    expect(find.byType(CreateCustomerPage), findsOneWidget);

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('This field is required.'), findsNWidgets(2));

    await tester.enterText(find.byType(TextFormField).at(0), 'Rana Hassan');
    await tester.enterText(find.byType(TextFormField).at(2), 'invalid-email');
    await tester.enterText(find.byType(TextFormField).at(3), '12 Nile Street');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter a valid email address.'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).at(2),
      'rana@example.com',
    );
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(CreateCustomerPage), findsOneWidget);
    expect(find.text('The change could not be saved.'), findsOneWidget);
    expect(
      tester.widgetList<TextFormField>(find.byType(TextFormField)).first.controller!.text,
      'Rana Hassan',
    );
    expect(tester.takeException(), isNull);
  });

  test('customer UI strings have English and German entries', () {
    const AppLocalizations en = AppLocalizationsEn();
    const AppLocalizations de = AppLocalizationsDe();
    expect(en.customersCountLabel(1), '1 customer');
    expect(en.customersCountLabel(2), '2 customers');
    expect(de.customersCountLabel(1), '1 Kunde');
    expect(de.customersCountLabel(2), '2 Kunden');
    expect(en.searchCustomersHint, contains('email'));
    expect(de.searchCustomersHint, contains('E-Mail'));
    expect(en.customerRequiredFieldsHint, isNotEmpty);
    expect(de.customerRequiredFieldsHint, isNotEmpty);
  });
}

Future<void> _registerCustomersCubit(_CustomersRepositoryFake repository) async {
  await sl.unregister<CustomersCubit>();
  sl.registerFactory<CustomersCubit>(
    () => CustomersCubit(
      getCustomers: GetCustomers(repository),
      getCustomerById: GetCustomerById(repository),
      createCustomer: CreateCustomer(repository),
      updateCustomer: UpdateCustomer(repository),
      deleteCustomer: DeleteCustomer(repository),
      refreshCustomers: RefreshCustomers(repository),
    ),
  );
}

class _CustomersRepositoryFake implements CustomersRepository {
  final StreamController<List<Customer>> _customers =
      StreamController<List<Customer>>.broadcast(sync: true);
  Object? createError;

  void emitCustomers(List<Customer> customers) => _customers.add(customers);

  void emitError(Object error) => _customers.addError(error);

  Future<void> dispose() => _customers.close();

  @override
  Stream<List<Customer>> watchCustomers() => _customers.stream;

  @override
  Stream<Customer?> watchCustomerById(String id) => Stream<Customer?>.value(null);

  @override
  Future<Customer?> getCustomerById(String id) async => null;

  @override
  Future<Customer> createCustomer({
    required String name,
    required String address,
    String? phone,
    String? email,
    String? city,
    String? postalCode,
    String? notes,
  }) async {
    if (createError != null) throw createError!;
    throw UnsupportedError('This fake is used for failure-path coverage.');
  }

  @override
  Future<void> updateCustomer(Customer customer) async {}

  @override
  Future<void> deleteCustomer(String id) async {}

  @override
  Future<void> refreshFromRemote() async {}

  @override
  Future<int> countLinkedJobs(String customerId) async => 0;
}

void _testCustomers(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}
