import 'package:flutter/material.dart';

/// Centered spinner shown while jobs are being loaded.
class JobsLoadingView extends StatelessWidget {
  const JobsLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}
