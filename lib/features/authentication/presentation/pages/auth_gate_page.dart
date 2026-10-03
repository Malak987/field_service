import 'package:field_service/app/di/injection.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_state.dart';
import 'package:field_service/features/authentication/presentation/pages/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:field_service/features/admin/presentation/pages/admin_home_page.dart';
import 'package:field_service/features/technician/presentation/pages/technician_home_page.dart';
class AuthGatePage extends StatelessWidget {
  const AuthGatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<AuthenticationCubit>()..checkCurrentUser(),
      child: const _AuthGateView(),
    );
  }
}

class _AuthGateView extends StatelessWidget {
  const _AuthGateView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthenticationCubit, AuthenticationState>(
      builder: (context, state) {
        switch (state.status) {
          case AuthenticationStatus.initial:
          case AuthenticationStatus.loading:
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );

          case AuthenticationStatus.unauthenticated:
            return const LoginPage();

          case AuthenticationStatus.failure:
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Something went wrong.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          context
                              .read<AuthenticationCubit>()
                              .checkCurrentUser();
                        },
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                ),
              ),
            );

          case AuthenticationStatus.authenticated:
            final user = state.user;

            if (user == null) {
              return const LoginPage();
            }

            if (user.isAdmin) {
              return const AdminHomePage();
            }

            if (user.isTechnician) {
              return const TechnicianHomePage();
            }

            return const Scaffold(
              body: Center(
                child: Text(
                  'Unknown user role.',
                ),
              ),
            );
        }
      },
    );
  }
}