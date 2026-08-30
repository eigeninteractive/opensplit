import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// Opens [name] with the platform SQLite implementation.
QueryExecutor openPlatformDatabase(String name) => driftDatabase(
  name: name,
  web: DriftWebOptions(
    sqlite3Wasm: Uri.parse('sqlite3.wasm'),
    driftWorker: Uri.parse('drift_worker.js'),
  ),
);
