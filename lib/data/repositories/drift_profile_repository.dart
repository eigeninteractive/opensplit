import 'package:drift/drift.dart';

import '../../domain/models/profile.dart';
import '../local/database.dart';

final class DriftProfileRepository {
  DriftProfileRepository(this._db);

  final AppDatabase _db;

  Future<Profile?> byId(String profileId) async {
    final row = await (_db.select(
      _db.profiles,
    )..where((t) => t.id.equals(profileId))).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  Stream<Profile?> watch(String profileId) =>
      (_db.select(_db.profiles)..where((t) => t.id.equals(profileId)))
          .watchSingleOrNull()
          .map((row) => row == null ? null : _toDomain(row));

  Future<void> upsert(Profile profile) async {
    await _db
        .into(_db.profiles)
        .insertOnConflictUpdate(
          ProfilesCompanion.insert(
            id: profile.id,
            displayName: profile.displayName,
            avatarUrl: Value(profile.avatarUrl),
            upiVpa: Value(profile.upiVpa),
          ),
        );
  }

  Profile _toDomain(ProfileRow row) => Profile(
    id: row.id,
    displayName: row.displayName,
    avatarUrl: row.avatarUrl,
    upiVpa: row.upiVpa,
  );
}
