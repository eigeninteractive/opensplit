import 'package:drift/drift.dart';

import '../../domain/models/profile.dart';
import '../local/database.dart';
import '../sync/outbox_queue.dart';

final class DriftProfileRepository {
  DriftProfileRepository(this._db, {this.outbox});

  final AppDatabase _db;
  final OutboxQueue? outbox;

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

  /// Every locally known profile as a point-in-time lookup.
  Future<Map<String, Profile>> all() async {
    final rows = await _db.select(_db.profiles).get();
    return {for (final row in rows) row.id: _toDomain(row)};
  }

  Future<void> upsert(Profile profile) => _db.transaction(() async {
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
    await outbox?.enqueue(OutboxTarget.profile, profile.id);
  });

  Profile _toDomain(ProfileRow row) => Profile(
    id: row.id,
    displayName: row.displayName,
    avatarUrl: row.avatarUrl,
    upiVpa: row.upiVpa,
    updatedAt: row.updatedAt,
  );
}
