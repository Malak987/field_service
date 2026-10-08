import 'dart:convert';

import 'package:field_service/features/employees/data/datasources/employees_remote_data_source.dart';
import 'package:field_service/features/employees/data/models/employee_model.dart';
import 'package:field_service/features/employees/domain/entities/employee.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Technician selector data contract: the display names come EXACTLY from
/// `public.employees.name` (the single source of truth) — never hardcoded,
/// never invented, never derived from the employee code. Only rows with an
/// unexpectedly empty name fall back to their employee code.
void main() {
  group('EmployeeModel', () {
    test('maps employees.name exactly as stored (no invented names)', () {
      final Employee employee = EmployeeModel.fromMap(<String, dynamic>{
        'id': 'emp-max',
        'name': 'Max Müller',
        'employee_code': 'TECH-001',
        'role': 'technician',
        'is_active': true,
      });

      expect(employee.name, 'Max Müller');
      expect(employee.displayName, 'Max Müller');
      expect(employee.employeeCode, 'TECH-001');
      expect(employee.isTechnician, isTrue);
      expect(employee.isActive, isTrue);
    });

    test('empty name falls back to the employee code (data problem, not a '
        'fake name)', () {
      final Employee employee = EmployeeModel.fromMap(<String, dynamic>{
        'id': 'emp-x',
        'name': null,
        'employee_code': 'TECH-007',
        'role': 'technician',
        'is_active': true,
      });

      expect(employee.hasMissingName, isTrue);
      expect(employee.displayName, 'TECH-007');
    });

    test('empty name without a code falls back to the id', () {
      final Employee employee = EmployeeModel.fromMap(<String, dynamic>{
        'id': 'emp-y',
        'name': '   ',
        'role': 'technician',
        'is_active': true,
      });

      expect(employee.displayName, 'emp-y');
    });

    test('a real name always wins over the code', () {
      const Employee employee = Employee(
        id: 'emp-a',
        name: ' Anna Schmidt ',
        employeeCode: 'TECH-002',
        role: 'technician',
      );

      expect(employee.displayName, 'Anna Schmidt');
    });
  });

  group('EmployeesRemoteDataSourceImpl', () {
    test('queries only ACTIVE technicians and maps real names', () async {
      late http.Request captured;
      final MockClient client = MockClient((http.Request request) async {
        captured = request;
        return http.Response(
          jsonEncode(<Object?>[
            <String, Object?>{
              'id': 'emp-max',
              'name': 'Max Müller',
              'employee_code': 'TECH-001',
              'role': 'technician',
              'is_active': true,
            },
            <String, Object?>{
              'id': 'emp-anna',
              'name': 'Anna Schmidt',
              'employee_code': 'TECH-002',
              'role': 'technician',
              'is_active': true,
            },
          ]),
          200,
          headers: <String, String>{'content-type': 'application/json'},
          // The PostgREST client inspects `response.request` — attach it.
          request: request,
        );
      });

      final EmployeesRemoteDataSource dataSource =
          EmployeesRemoteDataSourceImpl(
            SupabaseClient(
              'https://project.supabase.co',
              'test-anon-key',
              httpClient: client,
            ),
          );

      final List<Employee> technicians = await dataSource
          .getActiveTechnicians();

      // The selector receives exactly the stored names, in order.
      expect(technicians.map((Employee e) => e.displayName), <String>[
        'Max Müller',
        'Anna Schmidt',
      ]);

      // Server-side scoping: active technicians only, ordered by name.
      expect(captured.url.path, '/rest/v1/employees');
      expect(captured.url.queryParameters['select'], contains('name'));
      expect(captured.url.queryParameters['select'], contains('employee_code'));
      expect(captured.url.queryParameters['is_active'], 'eq.true');
      expect(captured.url.queryParameters['role'], 'eq.technician');
      expect(captured.url.queryParameters['order'], 'name.asc.nullslast');
    });
  });
}
