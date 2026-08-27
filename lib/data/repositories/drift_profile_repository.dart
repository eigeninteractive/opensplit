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

  /// Every profile this device knows about, keyed by id.
  ///
  /// The whole table, deliberately: it holds one row per person you share a
  /// group with, which is tens, and every screen that renders a name needs the
  /// lookup. Fetching them per member would be a query per row of every list.
  Stream<Map<String, Profile>> watchAll() => _db
      .select(_db.profiles)
      .watch()
      .map((rows) => {for (final row in rows) row.id: _toDomain(row)});

  Future<void> upsert(Profile profile) async {
    await _db
        .into(_db.profiles)
        .insertOnConflictUpdate(
          ProfilesCompanion.insert(
            id: profile.id,
            displayName: Value(profile.displayName),
            avatarUrl: Value(profile.avatarUrl),
            upiVpa: Value(profile.upiVpa),
            updatedAt: Value(profile.updatedAt),
          ),
        );
  }

  Profile _toDomain(ProfileRow row) => Profile(
    id: row.id,
    displayName: row.displayName,
    avatarUrl: row.avatarUrl,
    upiVpa: row.upiVpa,
    updatedAt: row.updatedAt,
  );
}
