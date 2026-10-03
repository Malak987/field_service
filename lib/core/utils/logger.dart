import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Thin logging facade used across the application.
///
/// Why not `print`: `dart:developer` output is structured, visible in DevTools
/// and in the IDE console, and can be filtered by name. Debug and info messages
/// are dropped in release builds; warnings and errors are kept and always carry
/// their `error` and `stackTrace` so a crash reporter can be attached later
/// without touching any call site.
///
/// Phase 3 status: implemented and used by `main()`; observability features
/// (remote reporting, breadcrumbs) arrive in a later phase.
abstract final class AppLogger {
  static const String _name = 'field_service';

  /// Development tracing. Not emitted in release builds.
  static void debug(String message) {
    if (kDebugMode) {
      developer.log(message, name: _name, level: 500);
    }
  }

  /// Notable lifecycle events (app start, sync run finished, ...).
  static void info(String message) {
    if (kDebugMode) {
      developer.log(message, name: _name, level: 800);
    }
  }

  /// Something unexpected but recoverable (a retried sync push, a stale cache).
  static void warning(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: _name,
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// A failure that requires attention.
  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: _name,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
