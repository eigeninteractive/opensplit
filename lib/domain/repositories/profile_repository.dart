import '../models/profile.dart';

abstract interface class ProfileRepository {
  Future<Profile?> byId(String profileId);

  Stream<Profile?> watch(String profileId);

  Future<void> upsert(Profile profile);
}
