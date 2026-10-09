import 'package:field_service/core/theme/app_colors.dart';
import 'package:field_service/core/theme/app_dimensions.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_cubit.dart';
import 'package:field_service/features/authentication/presentation/cubit/authentication_state.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Primary action button that subscribes only to the loading flag of
/// [AuthenticationCubit] so loading transitions do not rebuild the parent page.
///
/// Loading keeps the exact same burgundy surface and height (only the label is
/// replaced by a small spinner), so the CTA never shifts the layout, cannot be
/// double-tapped and still reads as "this is happening on brand".
class AuthLoadingButton extends StatelessWidget {
  const AuthLoadingButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoadingOverride,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Optional explicit loading flag when used outside [AuthenticationCubit].
  final bool? isLoadingOverride;

  @override
  Widget build(BuildContext context) {
    if (isLoadingOverride != null) {
      return _buildButton(context, isLoading: isLoadingOverride!);
    }

    return BlocSelector<AuthenticationCubit, AuthenticationState, bool>(
      selector: (AuthenticationState state) => state.isLoading,
      builder: (BuildContext context, bool isLoading) {
        return _buildButton(context, isLoading: isLoading);
      },
    );
  }

  Widget _buildButton(BuildContext context, {required bool isLoading}) {
    if (!isLoading) {
      return AuthPrimaryButton(label: label, icon: icon, onPressed: onPressed);
    }

    return SizedBox(
      height: AppDimensions.buttonHeight,
      width: double.infinity,
      child: FilledButton(
        // Disabled while in flight — duplicate submissions are impossible.
        onPressed: null,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary,
          disabledForegroundColor: Colors.white,
        ),
        child: SizedBox(
          width: AppDimensions.buttonSpinnerSize,
          height: AppDimensions.buttonSpinnerSize,
          child: const CircularProgressIndicator(
            strokeWidth: AppDimensions.spinnerStrokeWidth,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
