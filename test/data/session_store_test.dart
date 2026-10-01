import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/data/auth/session_store.dart';
import 'package:opensplit_api/opensplit_api.dart' show Account;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final account = Account(id: 'acct-1', isAnonymous: true, email: null);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the stored session', () {
    test('keeps the token out of the preferences', () async {
      final preferences = await SharedPreferences.getInstance();
      final vault = MemoryTokenVault();
      final store = await SessionStore.load(preferences, vault: vault);

      await store.write(StoredSession(account: account, token: 'secret-token'));

      expect(await vault.read(), 'secret-token');
      for (final key in preferences.getKeys()) {
        expect('${preferences.get(key)}', isNot(contains('secret-token')));
      }
    });

    test('comes back whole on the next launch', () async {
      final preferences = await SharedPreferences.getInstance();
      final vault = MemoryTokenVault();
      await (await SessionStore.load(
        preferences,
        vault: vault,
      )).write(StoredSession(account: account, token: 'secret-token'));

      final restored = (await SessionStore.load(
        preferences,
        vault: vault,
      )).read();

      expect(restored?.account.id, 'acct-1');
      expect(restored?.token, 'secret-token');
    });

    test('signing out forgets the account and the token', () async {
      final preferences = await SharedPreferences.getInstance();
      final vault = MemoryTokenVault();
      final store = await SessionStore.load(preferences, vault: vault);
      await store.write(StoredSession(account: account, token: 'secret-token'));

      await store.write(null);

      expect(store.read(), isNull);
      expect(await vault.read(), isNull);
    });

    test('an account whose token is missing reads as having none', () async {
      final preferences = await SharedPreferences.getInstance();
      await (await SessionStore.load(
        preferences,
        vault: MemoryTokenVault(),
      )).write(StoredSession(account: account, token: 'secret-token'));

      // A restored backup: the preferences came back, the Keystore did not.
      final restored = (await SessionStore.load(
        preferences,
        vault: MemoryTokenVault(),
      )).read();

      expect(restored?.account.id, 'acct-1');
      expect(restored?.token, isNull);
    });
  });
}
