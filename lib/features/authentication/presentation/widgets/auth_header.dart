import 'package:field_service/core/extensions/build_context_extensions.dart';
import 'package:field_service/core/theme/app_spacing.dart';
import 'package:field_service/features/authentication/presentation/widgets/auth_logo.dart';
import 'package:flutter/material.dart';

/// Brand block at the top of every authentication screen.
///
/// Hierarchy: logo → generous breathing room → screen title → short,
/// reassuring subtitle. A subtle fade/slide entrance gives the screen a
/// composed first impression without ever blocking interaction (the
/// animation completes on its own and ignores pointers while running).
class AuthHeader extends StatefulWidget {
  const AuthHeader({required this.title, required this.subtitle, super.key});

  final String title;
  final String subtitle;

  @override
  State<AuthHeader> createState() => _AuthHeaderState();
}

class _AuthHeaderState extends State<AuthHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _entrance,
    curve: Curves.easeOutCubic,
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(_fade);

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color subtitleColor = context.colors.onSurfaceVariant;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const AuthLogo(),
            const SizedBox(height: AppSpacing.xxxl),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: context.textStyles.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              widget.subtitle,
              textAlign: TextAlign.center,
              style: context.textStyles.bodyMedium?.copyWith(
                color: subtitleColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
