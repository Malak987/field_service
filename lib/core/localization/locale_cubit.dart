import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists and broadcasts the user's selected application [Locale].
///
/// Kept outside individual feature screens so switching language immediately
/// updates `MaterialApp.router` and survives application restarts.
class LocaleCubit extends Cubit<Locale> {
  LocaleCubit({
    SharedPreferences? preferences,
    Locale initialLocale = const Locale('en'),
  }) : _preferences = preferences,
       super(_resolveInitialLocale(preferences, initialLocale));

  static const String _storageKey = 'app_selected_locale_code';

  SharedPreferences? _preferences;

  static Locale _resolveInitialLocale(
    SharedPreferences? preferences,
    Locale fallback,
  ) {
    final String? savedCode = preferences?.getString(_storageKey);
    if (savedCode != null && _isSupportedCode(savedCode)) {
      return Locale(savedCode);
    }
    return fallback;
  }

  static bool _isSupportedCode(String languageCode) {
    return AppLocalizations.supportedLocales.any(
      (Locale locale) => locale.languageCode == languageCode,
    );
  }

  /// Loads persisted locale from [SharedPreferences] if it was not injected
  /// synchronously at construction time.
  Future<void> loadSavedLocale() async {
    try {
      final SharedPreferences prefs =
          _preferences ?? await SharedPreferences.getInstance();
      _preferences = prefs;
      final String? savedCode = prefs.getString(_storageKey);
      if (savedCode != null &&
          _isSupportedCode(savedCode) &&
          savedCode != state.languageCode) {
        emit(Locale(savedCode));
      }
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to read persisted locale preference.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Updates the active application language and persists the choice locally.
  Future<void> setLocale(Locale locale) async {
    if (!_isSupportedCode(locale.languageCode)) {
      return;
    }
    if (state.languageCode != locale.languageCode) {
      emit(Locale(locale.languageCode));
    }
    try {
      final SharedPreferences prefs =
          _preferences ?? await SharedPreferences.getInstance();
      _preferences = prefs;
      await prefs.setString(_storageKey, locale.languageCode);
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to persist locale preference.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Convenience toggle between English (`en`) and German (`de`).
  Future<void> toggleLanguage() {
    final String nextCode = state.languageCode == 'de' ? 'en' : 'de';
    return setLocale(Locale(nextCode));
  }
}
