import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/data/auth/supabase_auth_service.dart';

void main() {
  group('the address Google sends the browser back to', () {
    test('keeps the origin it left from, so local runs stay local', () {
      expect(
        googleRedirectUrl(Uri.parse('http://localhost:5000/welcome'), '/'),
        'http://localhost:5000/welcome?from=%2F',
      );
    });

    test('carries the /app prefix only where the client is served under it', () {
      expect(
        googleRedirectUrl(
          Uri.parse('https://opensplit.web.app/app/welcome'),
          '/',
        ),
        'https://opensplit.web.app/app/welcome?from=%2F',
      );
      expect(
        googleRedirectUrl(Uri.parse('https://opensplit.web.app/welcome'), '/'),
        'https://opensplit.web.app/welcome?from=%2F',
      );
    });

    test('preserves the invite it was opened from', () {
      // The whole reason the destination travels rather than being rebuilt:
      // somebody with no session tapped a friend's link, and the sign-in has
      // to end on the invite rather than on the home screen.
      expect(
        googleRedirectUrl(
          Uri.parse('https://opensplit.web.app/app/welcome?from=/join/abc123'),
          '/join/abc123',
        ),
        'https://opensplit.web.app/app/welcome?from=%2Fjoin%2Fabc123',
      );
    });

    test('drops any port-less or path-bearing surprises in the origin', () {
      // `Uri.base` on a deep route must not leak that route into the target.
      expect(
        googleRedirectUrl(
          Uri.parse('https://opensplit.web.app/app/g/42/settings'),
          '/g/42/settings',
        ),
        'https://opensplit.web.app/app/welcome?from=%2Fg%2F42%2Fsettings',
      );
    });
  });
}
