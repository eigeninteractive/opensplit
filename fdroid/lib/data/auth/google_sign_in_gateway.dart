import 'package:opensplit/data/auth/google_credential.dart';

export 'package:opensplit/data/auth/google_credential.dart';

/// This build uses email codes for sign-in and account recovery.
class GoogleSignInGateway implements GoogleTokenSource {
  static bool get isOffered => false;

  @override
  Future<GoogleCredential?> obtainIdToken() async => null;
}
