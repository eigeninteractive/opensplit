import 'package:drift/drift.dart';

import '../local/database.dart';
import '../sync/outbox_queue.dart';

final class DriftProfileRepository {
  DriftProfileRepository(this._db, {this.outbox});

  final AppDatabase _db;
  final OutboxQueue? outbox;

  Future<Profile?> byId(String profileId) => (_db.select(
    _db.profiles,
  )..where((t) => t.id.equals(profileId))).getSingleOrNull();

  Stream<Profile?> watch(String profileId) => (_db.select(
    _db.profiles,
  )..where((t) => t.id.equals(profileId))).watchSingleOrNull();

  /// Every profile this device knows about, keyed by id.
  Stream<Map<String, Profile>> watchAll() =>
      _db.select(_db.profiles).watch().map(_byId);

  /// Every locally known profile as a point-in-time lookup.
  Future<Map<String, Profile>> all() async =>
      _byId(await _db.select(_db.profiles).get());

  static Map<String, Profile> _byId(List<Profile> rows) => {
    for (final row in rows) row.id: row,
  };

  Future<void> upsert(Profile profile) => _db.transaction(() async {
    await _db
        .into(_db.profiles)
        .insertOnConflictUpdate(
          ProfilesCompanion.insert(
            id: profile.id,
            displayName: Value(profile.displayName),
            upiVpa: Value(profile.upiVpa),
            updatedAt: Value(profile.updatedAt),
          ),
        );
    await outbox?.enqueue(OutboxTarget.profile, profile.id);
  });
}
