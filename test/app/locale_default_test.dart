import 'package:field_service/core/localization/app_localizations.dart';
import 'package:field_service/core/localization/locale_cubit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The default-language contract.
///
/// The app ships German-first: on a first launch with no saved preference the
/// UI is German, English is the only alternative, and an explicit user choice
/// always wins over the default. `AppTestHarness` pins English for the other
/// suites, so this is the one place the production default is asserted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('no saved preference resolves to German', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final LocaleCubit cubit = LocaleCubit();
    addTearDown(cubit.close);

    expect(cubit.state, const Locale('de'));
    expect(AppLocalizations.supportedLocales.first, const Locale('de'));
  });

  test('a saved preference wins over the German default', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app_selected_locale_code': 'en',
    });
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    final LocaleCubit cubit = LocaleCubit(preferences: preferences);
    addTearDown(cubit.close);

    expect(cubit.state, const Locale('en'));
  });

  test('the default stays overridable for an embedded host', () {
    final LocaleCubit cubit = LocaleCubit(
      initialLocale: const Locale('en'),
    );
    addTearDown(cubit.close);

    expect(cubit.state, const Locale('en'));
  });

  test('an unsupported saved code falls back to the default', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app_selected_locale_code': 'fr',
    });
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    final LocaleCubit cubit = LocaleCubit(preferences: preferences);
    addTearDown(cubit.close);

    expect(cubit.state, const Locale('de'));
  });
}
