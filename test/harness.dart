import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opensplit/application/providers.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The account a widget test is signed in as.
///
/// A fixed uuid rather than a random one so that a failure message naming it is
/// the same failure message every time.
const testAccountId = '00000000-0000-4000-8000-00000000dead';

/// Everything the app needs to render as a signed-in user with no backend.
///
/// A session is not optional any more. The app used to manufacture one on
/// startup, so a test could get away with overriding storage alone; now nobody
/// is anybody until they choose, and a test that skips this lands on the
/// welcome screen and finds none of the widgets it came to look for.
///
/// [signedInProvider] and [currentAccountIdProvider] are overridden rather than
/// the session behind them because there is no Supabase in a widget test at
/// all: `authServiceProvider` is null, so the real controller can only ever
/// answer "nobody".
/// Returns a scope, not a list of overrides: `Override` is not part of
/// flutter_riverpod's public API, so it cannot be named in a signature here.
Widget signedInApp({
  required AppDatabase db,
  required SharedPreferences prefs,
  required Widget child,
  String accountId = testAccountId,
}) => ProviderScope(
  overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    // Supplied directly, so the test's in-memory database is used instead of
    // the per-account file the app would open.
    appDatabaseProvider.overrideWithValue(db),
    signedInProvider.overrideWithValue(true),
    currentAccountIdProvider.overrideWithValue(accountId),
  ],
  child: child,
);
