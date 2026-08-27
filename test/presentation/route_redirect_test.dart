import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/presentation/navigation.dart';

void main() {
  test('native App Links lose only the app base prefix', () {
    expect(
      redirectAppRoute(
        Uri.parse('/app/join/token?source=share'),
        signedIn: false,
      ),
      '/join/token?source=share',
    );
    expect(redirectAppRoute(Uri.parse('/app'), signedIn: true), '/');
    expect(redirectAppRoute(Uri.parse('/app/'), signedIn: true), '/');
  });

  test('authentication returns to the original protected destination', () {
    final destination = Uri.parse('/g/group/e/entry?tab=history');
    final welcome = Uri.parse(redirectAppRoute(destination, signedIn: false)!);
    expect(welcome.path, '/welcome');
    expect(welcome.queryParameters['from'], destination.toString());
    expect(redirectAppRoute(welcome, signedIn: true), destination.toString());
  });

  test(
    'invite previews remain public and return URLs cannot leave the app',
    () {
      expect(
        redirectAppRoute(Uri.parse('/join/token'), signedIn: false),
        isNull,
      );
      for (final unsafe in [
        'https://attacker.example',
        '//attacker.example',
        'relative',
        '/welcome',
        '/app/welcome',
      ]) {
        expect(safeReturnLocation(unsafe), '/', reason: unsafe);
      }
    },
  );
}
